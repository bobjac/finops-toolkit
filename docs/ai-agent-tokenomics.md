# AI Agent Tokenomics — agent-level token cost for Microsoft Foundry

## The problem

FinOps teams can already see AI spend at the **model** level (for example, "gpt-5-mini
cost $X this month"). What they cannot see is which **agent** spent that money.

Modern Foundry / Agent Framework workloads are multi-agent: a parent orchestrator
(for example, a Contoso travel concierge) fans out to subagents — a flight agent, a
hotel agent, a car-rental agent — each calling a model. A single model deployment is
therefore shared across many agents, so model-level cost cannot answer the questions
FinOps actually asks:

- Which agent is driving spend?
- What does one conversation (session) cost?
- Which subagent should we optimize first?

### Why the existing telemetry does not solve it

- **Cognitive Services platform metrics** (the source behind the popular AI Foundry
  Grafana dashboard) only expose the dimensions `ModelName`, `ModelDeploymentName`,
  and `StatusCode`. There is **no agent or session dimension**, so no rewrite of that
  dashboard can attribute spend to an agent.
- The **new project-level "AI Agents" metrics** (`AgentInputTokens` /
  `AgentOutputTokens`, in preview) finally add an `AgentId` dimension, but:
  - subagents invoked **as tools** collapse their tokens into the parent agent (you
    only get `AgentToolCalls`, a *count*, per `ToolName` — not tokens or dollars);
  - the token metrics carry no `ThreadId`, so tokens cannot be tied to a conversation;
  - they are pre-aggregated metrics, and `DS Export` is off, so they cannot be
    exported to Log Analytics to rebuild a query.

**Agent identity and per-agent token usage only exist in the `gen_ai` OpenTelemetry
traces** that Foundry / Agent Framework emit. This work reads those traces and turns
them into agent-level, FOCUS-shaped cost.

## What was built

Two artifacts were added to the branch. Both are self-contained and deploy against a
standard Application Insights / Log Analytics resource that receives Foundry traces.

| File | Purpose |
| --- | --- |
| `src/queries/catalog/ai-agent-token-cost.kql` | The core query: turns `gen_ai` traces into per-agent token cost, projected into FOCUS-style columns. |
| `src/workbooks/optimization/AiAgentTokenomics/AiAgentTokenomics.workbook` | An Azure Monitor workbook that renders that query as an interactive, browser-based dashboard. |

### 1. The KQL query — `ai-agent-token-cost.kql`

The query reads the token-bearing spans from the Application Insights `dependencies`
table (equivalently `AppDependencies` in Log Analytics) and produces one row per
agent / model / cost center.

How it works, step by step:

1. **Select the AI spans.** Filter to spans whose `type` starts with `GenAI` — the
   agent-invocation and model-call spans emitted by the OpenTelemetry `gen_ai`
   instrumentation.
2. **Parse the trace attributes.** The attributes land inside `customDimensions`
   as JSON. The query reads **both attribute vocabularies** and `coalesce()`s them,
   because the two producers differ:
   - **Foundry-native project tracing** (enable an Application Insights connection on
     the Foundry project — no workload change): `microsoft.gen_ai.main_agent.id` /
     `.name`, `microsoft.gen_ai.main_agent.conversation_id`, `microsoft.session.id`,
     `microsoft.tenant.id`, `microsoft.foundry.project.id`, `gen_ai.response.model`,
     `gen_ai.usage.*` (with `gen_ai.usage.cache_read.input_tokens` for cached input).
     These spans have type `InProc`, name `chat <model>`.
   - **OpenTelemetry OpenAI instrumentation** (self-hosted / externally hosted
     agents): `gen_ai.agent.id` / `.name`, `gen_ai.conversation.id`,
     `gen_ai.request.model`, `gen_ai.usage.*`, plus any custom `finops.team` /
     `finops.cost_center` tags.

   Rather than filter on span type (which differs between the two), the query selects
   token-bearing spans by the presence of `gen_ai.usage.*` tokens, so it works against
   either source. Extracted fields: which agent, which session, which model, token
   usage, and — for Foundry-native traces — tenant and project for free.
3. **Aggregate per agent.** Sum tokens and count calls and distinct sessions, grouped
   by agent, model, team, and cost center.
4. **Price it.** Join to an inline rate-card `datatable` (USD per 1M tokens, gpt-5
   family list prices) via `lookup kind=leftouter`, and compute input, cached, and
   output cost separately, since cached input is billed at a lower rate.
5. **Shape it to FOCUS.** Project the result into FOCUS-style columns
   (`ConsumedQuantity`, `ConsumedUnit`, `EffectiveCost`, `BillingCurrency`,
   `ChargeCategory`, `ServiceCategory`) plus agent-level `x_` extensions
   (`x_AgentId`, `x_AgentName`, `x_CostCenter`, `x_Team`, and — from Foundry-native
   traces — `x_TenantId` and `x_ProjectId`), so the output slots into the
   FinOps Toolkit's FOCUS-aligned data model.

The query header documents a **toolkit-integration path**: in a deployed FinOps Hub,
replace the inline rate card with the authoritative `Costs()` function so pricing stays
canonical, and land the agent-level rows as FOCUS records via the hub ingestion
pipeline.

### 2. The workbook — `AiAgentTokenomics.workbook`

An Azure Monitor workbook that runs the query live and renders it as an interactive
dashboard in the Azure portal (works in any browser, including macOS). It contains
seven tiles:

| Tile | Visualization | Shows |
| --- | --- | --- |
| Header | text | Title and description |
| Summary | grid | KPIs — calls, sessions, total tokens, estimated cost |
| Effective cost by agent | bar chart | Which agents cost the most |
| Cost by cost center | pie chart | Business-unit / cost-center split |
| Tokens by model | bar chart | Input vs output tokens per model |
| Cost over time by agent | time chart | Spend trend per agent |
| Agent × model × cost center | grid | Full FOCUS-shaped breakdown |

All tiles are scoped to the Application Insights resource that receives the traces, so
they update automatically as new agent-tagged calls arrive (roughly 2–3 minutes of
ingestion latency).

## How it fits together (data flow)

```
Foundry / Agent Framework workload
  │  OpenTelemetry gen_ai instrumentation
  │  (gen_ai.agent.id, gen_ai.conversation.id, gen_ai.usage.*, finops.*)
  ▼
Application Insights  (dependencies / AppDependencies)
  │
  ├─ ai-agent-token-cost.kql  ──▶  per-agent, FOCUS-shaped token cost
  │
  ▼
AiAgentTokenomics.workbook  ──▶  interactive per-agent dashboard in the Azure portal
```

Optional next hop for a full toolkit deployment: swap the inline rate card for the
hub's `Costs()` pricing and ingest the agent-level rows into the FinOps Hub as FOCUS
records with `x_Agent*` extensions.

## Why this is the right level of granularity

The token counts — and therefore the dollars — live on the **model-call (`chat`)
spans**. The surrounding **`invoke_agent`** and **`execute_tool`** spans provide the
structure that says *which agent* and *which tool* those tokens belong to. Because a
single agent turn often triggers extra model calls (a tool round-trip is
`call model → run tool → call model again`), and because subagents are invoked as
tools, only the full span tree lets you attribute every model call to the correct
agent and roll subagent cost up to its parent. That tree exists solely in the
`gen_ai` traces this solution reads — which is exactly why platform metrics, even the
new preview agent metrics, cannot replace it.
