# Demo script: From a coding-agent proposal to a measured decision

**Target: 4 minutes 30 seconds.** Show the workflow, not a tour of dashboards:

**FinOps toolkit operational cost data -> coding-agent planner -> bounded code
proposal -> controlled experiment -> evidence-backed decision.**

The experiment is already complete. You don't need to rerun it or execute
commands to record this story. The assistant prepares the views off camera;
you record them and read the narration below.

**Preparation status:** This is the rewritten script, not a claim that the
agent/MCP and workbook scenes have been rehearsed. Those views still need a
read-only check. The existing offline presentation and its `narration.html`
remain unchanged and are a fallback, not this new workflow script.

## What the audience should understand

> We expose FinOps toolkit operational cost data to a coding-agent planner
> through bounded, read-only tools, then test its proposed code change against
> measured cost, answer quality, and performance before recommending adoption.

The [existing toolkit](../../docs-mslearn/toolkit/finops-toolkit-overview.md#available-tools)
provides cost-data infrastructure, reporting, optimization recommendations, and
automation. It also has agent integration. Don't describe it as only a dashboard
or claim this PoC invented its first agent connection.

The gap addressed here is narrower: cost analysis or a recommendation alone
doesn't establish whether a particular repository change lowers cost while
preserving behavior. Our PoC adds bounded operational context for the planner
and a controlled experiment/evaluator loop. MCP and the workbook help demonstrate
that workflow; neither is the whole contribution. The demo's historical cost
context is synthetic, not current billed spend for the sample application.

## Screen order

Have the assistant stage these views before recording. Keep narration on paper
or a second display outside the captured area. Don't wait for agent responses
or run an experiment during the take.

| Scene | Time | Screen |
|---|---|---|
| 1. The toolkit and the gap | 0:00-0:50 | Toolkit overview and data-to-planner flow, then original baseline `agents.py` |
| 2. The investigation | 0:50-1:35 | Coding-agent review, genuine read-only tool-call details, and original context provenance |
| 3. The proposal | 1:35-2:05 | Exact baseline-to-candidate diff |
| 4. The test | 2:05-2:45 | Previously completed GitHub experiment run and its completed job steps |
| 5. The decision | 2:45-3:45 | Workbook token usage, then the original evaluated comparison |
| 6. The safety check and value | 3:45-4:30 | Labeled missing-price replay, then the narrow diff or original decision |

These are six recording scenes across the real tools, **not** the six pages of
the offline presentation. The [Mac guide](record-on-mac.md) still supplies
microphone, capture, trimming, and export instructions. Use this document for
the workflow narration instead of the archived deck's `narration.html`.

## 1. The toolkit and the gap, 0:00-0:50

**Show first:** The [FinOps toolkit overview](../../docs-mslearn/toolkit/finops-toolkit-overview.md),
briefly, with this flow visible as an on-screen caption:

```text
FinOps toolkit: operational cost + pricing data
  -> bounded, read-only tools -> coding-agent planner
  -> proposed code change -> human-approved experiment -> measured decision
```

**Then show:** The [original baseline code](https://github.com/bobjac/finops-toolkit/blob/c9df575ea8fa90cfec45072085d9919e21a12068/hack/sample-multi-agent-workload/src/sample_workload/agents.py).
Enlarge the two places where `"schema": SCHEMA` supplies the full schema.
Use the historical baseline, not the current, already optimized checkout.
Don't edit anything.

**Say:**

> The Microsoft FinOps toolkit is an open-source collection for understanding
> and optimizing cloud costs. Its hubs organize cost data, and its reports,
> recommendations, and automation help teams act on it.
>
> But cost analysis alone doesn't prove a proposed code change will be cheaper.
>
> Our proof of concept exposes operational cost data to a coding-agent planner
> through bounded, read-only tools, then measures its proposal against a baseline.
>
> This demo uses synthetic historical cost data. Our sample sends the full
> database schema to both specialists. Can we send less context and keep
> the same correct answers?

**Action:** Point to the two schema arguments, then switch to the prepared
coding-agent review.

## 2. The investigation, 0:50-1:35

**Show:** A genuine completed read-only review of that original baseline.
Expand one actual Azure MCP Kusto query and its returned FinOps context.
Keep the original proposal's recorded context sources and dates available
beside it.

**On-screen label:** `New read-only review of the original baseline.
Measured experiment completed November 13, 2026.`

**Say when showing a genuine Azure MCP tool call:**

> First, the agent needs evidence, not just a prompt saying "make it cheaper."
> Here is a read-only Azure MCP query to the FinOps hub. This is synthetic
> historical cost context, not current application spend.

**If using only the original adapter response instead, say this opening:**

> First, the agent needs evidence, not just a prompt saying "make it cheaper."
> This is the original retained response from a bounded, read-only FinOps
> context adapter. I'm showing recorded evidence, not a live MCP call.

**Continue with either opening:**

> The original proposal had four bounded context tools: cost summary, resource
> costs, cached recommendations, and applicable pricing.
>
> The opportunity comes from inspecting the code. Historical costs provide
> context; they don't prove this change will save money. That's why the next
> step is a specific proposal and a controlled measurement.

**Action:** Show the actual tool name, bounded scope/query, returned data, and
historical label briefly. Don't scroll through pages of JSON.

**Accuracy rule:** The four original context tools are PowerShell adapters,
not four tools on a newly built MCP server. The plugin separately configures
the read-only Azure MCP Kusto integration. Never fabricate a tool-call card or
describe a new review as the original session that produced the experiment.

## 3. The proposal, 1:35-2:05

**Show:** The [exact source comparison](https://github.com/bobjac/finops-toolkit/compare/c9df575ea8fa90cfec45072085d9919e21a12068...79a087dce14212ac6f47d090860001dbfa0fb47b),
focused on `agents.py`. Show both changed schema arguments.

**Say:**

> The proposal is deliberately small: give each specialist only the complete
> table definitions approved for that question.
>
> These are the two changes. We aren't changing the model, database, agent
> topology, evaluation questions, or guardrails.
>
> The coding agent proposes the change. It doesn't independently deploy to
> production or authorize paid traffic. Publication, deployment, testing, and
> cleanup have separate human approvals.

**Action:** Point to one replacement, then the other. Don't ask the agent to
make another edit or create a new candidate.

## 4. The test, 2:05-2:45

**Show:** The [completed experiment run, attempt 1](https://github.com/bobjac/finops-toolkit/actions/runs/43351201733/attempts/1).
Open the completed experiment job and locate its measurement and cleanup
steps. Don't select **Re-run jobs** or dispatch another workflow.

**On-screen label:** `Previously completed controlled experiment`.

**Say:**

> This is the experiment that already ran, not a new test starting during
> this video.
>
> It measures the original baseline twice, then the candidate, using the
> same seven golden questions and fixed runtime conditions. Each pass has
> five expected answers and two expected nonanswers.
>
> The evaluator checks answer quality, HTTP errors, latency, price coverage,
> and baseline variation. Experiment-owned temporary apps are cleaned up.
> A cheaper result isn't enough: the candidate must pass the guardrails before
> the evaluator recommends accepting it.

**Action:** Hold on the successful completed job, then switch to usage.
The cleanup claim here is about the experiment's temporary apps, **not**
full teardown of the retained sample or foundation.

## 5. The decision, 2:45-3:45

**Show first:** The [workbook](https://portal.azure.com/#@/resource/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46/providers/Microsoft.Insights/workbooks/478410d0-a0ae-5679-89fe-eea6a576654c/workbook),
already filtered to the experiment and its November 13 measurement window.
Show the agent/model breakdown and token usage, not a stale current-price
total. If unavailable, use the archived usage table explicitly labeled as
archived. Don't describe the fallback as a live workbook.

**Say:**

> Application Insights captures model usage, and the workbook makes it visible
> alongside FinOps hub pricing. Here we can inspect consumption by agent and
> model. This view combines both baseline passes, so we use the evaluator's
> per-pass results for a fair comparison.

**Switch:** Open the original evaluated comparison. The archived deck's scene 4
is a readable view of it. Show cost per 1,000 successful evaluated answers,
quality, errors, price coverage, and p95.

**Say:**

> The evaluator supplies the decision, not the dashboard.
>
> Baseline mean cost was 1.2099 US dollars per thousand successful evaluated
> answers. The candidate was 1.1361: approximately 6.10 percent lower.
> All measured model consumption is included, including nonanswers.
>
> All golden-test quality checks passed, with zero HTTP errors and complete
> price coverage at evaluation time. The latency and improvement thresholds
> also passed. The original decision was Accept.
>
> These use the original recorded prices. They are model-only estimates,
> not a current-price quote or an invoice saving.

**Accuracy rules:** The workbook can combine both baseline passes. Don't
compare their combined cost or calls with one candidate pass as though the
workloads were equal. Its pricing freshness check uses today's clock;
selecting a historical time range doesn't make expired prices current.
The original evaluation is the authority for the historical cost decision.

## 6. The safety check and value, 3:45-4:30

**Show:** The archived deck's **Synthetic missing-price case**, then finish on
the exact code diff or original decision.

**Say:**

> It must also know when not to recommend a change. This isolated synthetic
> replay removes a required output-token price from a copy of the evidence.
> The result becomes Repeat with incomplete evidence. Unknown cost is not zero.
>
> That's what we built: a coding-agent proposal connected to FinOps context,
> controlled testing, and a traceable decision.
>
> Partners can reuse the sample, adapters, runner, and evaluator with another
> approved workload. This small sequential proof of concept excludes
> infrastructure and telemetry costs. Retained Azure resources still need
> separately approved cleanup. It isn't an autonomous production optimizer.

**Action:** Leave the final view visible for two quiet seconds, then stop
recording with **Control+Command+Escape**.

## Assistant preparation checklist

This is work for the assistant/operator, not commands for the person recording.
It is **not** permission to rerun the experiment, grant roles, deploy, refresh
prices, or invoke the application.

1. Stage the toolkit overview, the data-to-planner caption, the original
   baseline, and the exact diff. Don't switch the working tree to the baseline
   or alter the measured revisions. Keep the introduction to the toolkit brief;
   this isn't a tour of every component.
2. Rehearse a bounded read-only review. If demonstrating MCP, verify the
   configured Azure MCP Kusto connection and actual query access first.
   Capture a genuine successful call; stop on denied access rather than
   changing permissions or fabricating a response.
3. Use a labeled June 2024 synthetic historical cost query for the MCP example.
   Keep it separate from the recorded four-tool context handoff. Don't call
   stale recorded prices current, or imply this new query produced the old result.
4. Finish the agent response off camera. Label it a new read-only baseline
   review. Don't create a new proposal transcript and pass it off as original
   approval or measurement evidence.
5. Stage the completed GitHub run and the actual workbook. Use **TimeRange**
   containing **November 13, 2026, 02:30-03:05 UTC**, **Baseline** `baseline`,
   **Candidate** `candidate`, and this exact **Experiment**:

   ```text
   ef560d02b1a2088bd8b25fe0bc55173d91d5ede2c2673e36a78978c99b79f400
   ```

6. Check workbook rendering, data retention, filters, and privacy. If a
   required live view is unavailable, choose and label the recorded branch
   before the take; don't improvise a false live demonstration.
7. Verify the archived package and original figures. Keep its files and hashes
   unchanged. The package is at this persistent Mac location:

   ```text
   ~/Movies/FinOps demo/Archived experiment 43351201733
   ```

8. Use `index.html` for the archived fallback; `scene-4.html` for the original
   decision; and `scene-5.html` for the synthetic negative case. These work
   after a reboot without this coding session. Keep the whole folder together.
9. Keep this workflow script separate from the deck's older `narration.html`.
   Rehearse the chosen branches and transitions aloud; target 4:30 and keep
   the final video between three and five minutes.

Writing this script doesn't establish live access, a recorded video, portal
submission, new clean-rebuild evidence, or completion of
[issue #14](https://github.com/bobjac/finops-toolkit/issues/14).
