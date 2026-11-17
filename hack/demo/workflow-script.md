# Demo script: From a coding-agent proposal to a measured decision

**Target: 4 minutes 30 seconds.** Show the workflow, not a tour of dashboards:

**FinOps toolkit operational cost data -> coding-agent planner -> bounded code
proposal -> controlled experiment -> evidence-backed decision.**

The experiment is already complete. You don't need to rerun it or execute
commands to record this story. The assistant prepares the views off camera;
you record them and read the narration below.

**Use the click-by-click route below.** It uses the original recorded adapter
response, real source code and diff, the completed GitHub job, and archived
usage and decisions. No Terminal, PowerShell, Azure query, or new experiment
is required. The supporting files have persistent Mac locations listed below.

**About the earlier "expand one actual Azure MCP query" instruction:** There
isn't a verified, prepared MCP conversation to open yet. You haven't missed
a button or a file. Don't try to find that conversation or start a new one
while recording. The default route now shows the actual retained adapter
response, explicitly labeled as recorded evidence, not an MCP call or an
original planner conversation. The optional MCP/workbook route at the end
still needs a separate assistant-led rehearsal.

The existing offline presentation and its `narration.html` remain unchanged.
Use **this script**, not that older narration, for the workflow recording.

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

## Open these files and tabs before recording

Do these clicks off camera. Use Microsoft Edge or Google Chrome. The paths
below work after a reboot; they don't depend on a window opened by the
assistant. Keep narration on paper or a second display outside the capture.

There are two local folders. **Workflow recording files 43351201733** contains
the new introduction and unchanged copies of all four original adapter
responses. **Archived experiment 43351201733** is the existing, unchanged
presentation with usage and decisions.

1. Open your browser. Select **File > New Window**, or use **Command+N**.
   Keep this window dedicated to the nine tabs below. Don't use the green
   full-screen button.
2. In the first tab, use **Command+O**. In the Open dialog, use
   **Shift+Command+G**, paste this full path, and press **Return**. If the
   dialog remains open, select **Open** or press **Return** again:

   ```text
   ~/Movies/FinOps demo/Workflow recording files 43351201733/workflow-map.html
   ```

3. Use **Command+T** to add each subsequent tab in the table's order.
   For a website, right-click its link below and choose **Copy Link Address**
   or **Copy Link**, depending on your browser. In the new tab, use
   **Command+L**, paste the address, and press **Return**.
   For a local file, use **Command+O**, then **Shift+Command+G** as above.
   Append the table's filename to its folder path:

   ```text
   Workflow folder: ~/Movies/FinOps demo/Workflow recording files 43351201733/
   Archive folder:  ~/Movies/FinOps demo/Archived experiment 43351201733/
   ```

4. Confirm all nine tabs load before recording. Sign in to GitHub off camera
   if it asks. If GitHub is inaccessible, stop this route rather than starting
   a new workflow. The separate [offline Mac guide](record-on-mac.md) remains
   available.
5. In tab 3, enlarge the JSON text with **Command+Plus sign**; aim for
   **150%** browser zoom. Use **Command+F**, enter `"data"`, press **Return**,
   then **Escape**. Scroll until the returned `BilledCost`, `BillingCurrency`,
   and nearby historical-data warning fill the view together. This is a JSON
   text file, not a chat window. Browser versions may format JSON differently.
6. In tab 5, use **Command+F** to find `"schema": SCHEMA`. Press **Escape**.
   Confirm you're looking at the `agents.py` diff, not one of the other files.
   The removed full-schema arguments are red; the filtered replacements are
   green. Set browser zoom with **Command+Plus sign** or **Command+Minus sign**
   so they're readable.
7. In tab 6, leave the successful **experiment** job and its step list visible.
   Locate **Build, deploy, load, collect, clean up, and compare** and
   **Always verify cleanup of only the selected run-owned temporary apps**.
   You only need the completed step names; don't expand long logs.
8. Use **Command+1** to return to the introduction. Keep exactly these nine
   tabs in this window. **Command+1** through **Command+8** select those tabs;
   **Command+9** selects the last tab. Clicking the tabs also works.
9. Follow the Mac guide's [microphone and screen setup](record-on-mac.md#2-prepare-your-microphone-and-screen)
   and [short recording test](record-on-mac.md#3-make-a-short-recording-test).
   Check the capture rectangle against all nine tabs. Keep browser tabs,
   addresses, narration, and unrelated account information out of the crop,
   but keep evidence headings, historical labels, and results visible.

| Tab | Open this file or website | What you should see |
|---|---|---|
| 1 | Workflow folder: `workflow-map.html` ([source](workflow-map.html)) | **From operating cost to coding decisions** |
| 2 | [Original baseline `agents.py`, lines 150-175](https://github.com/bobjac/finops-toolkit/blob/c9df575ea8fa90cfec45072085d9919e21a12068/hack/sample-multi-agent-workload/src/sample_workload/agents.py#L150-L175) | Two original `"schema": SCHEMA` arguments |
| 3 | Workflow folder: `get_cost_summary.json` | Original response, tool `get_cost_summary`, `sample-history`, June 2024 dates, and returned cost row |
| 4 | Archive folder: `scene-3.html` | **One bounded, human-approved proposal** and the four recorded context-tool names |
| 5 | [Exact baseline-to-candidate comparison](https://github.com/bobjac/finops-toolkit/compare/c9df575ea8fa90cfec45072085d9919e21a12068...79a087dce14212ac6f47d090860001dbfa0fb47b) | `agents.py`: two filtered-schema replacements |
| 6 | [Completed experiment job](https://github.com/bobjac/finops-toolkit/actions/runs/43351201733/job/131642886198) | Successful **experiment** job from the original run |
| 7 | Archive folder: `scene-2.html` | **Azure usage, retained from the real measurement** |
| 8 | Archive folder: `scene-4.html` | **Original decision: ACCEPT** and **6.10%** |
| 9 | Archive folder: `scene-5.html` | **Synthetic missing-price case** and **REPEAT** |

The workflow folder also contains `get_cost_by_resource.json`,
`get_optimization_recommendations.json`, and `get_current_pricing.json`.
They're supporting originals; you don't need extra tabs for them. The tool
name `get_current_pricing` doesn't mean its recorded prices are current today.
Don't change any JSON, original dates, or files in the archive folder.
Local files should be opened through the Open dialog, not a `file://` link
from GitHub, which browsers can block.

## Screen order

These are six **story sections**, not six browser tabs or the archive's page
numbers. For example, workflow section 5 uses the archive's `scene-2.html`
and `scene-4.html`.

| Scene | Time | Screen |
|---|---|---|
| 1. The toolkit and the gap | 0:00-0:50 | Tabs 1 -> 2: introduction, then original code |
| 2. The investigation | 0:50-1:35 | Tabs 3 -> 4: recorded adapter response, then context-tool summary |
| 3. The proposal | 1:35-2:05 | Tab 5: exact code diff |
| 4. The test | 2:05-2:45 | Tab 6: original completed experiment job |
| 5. The decision | 2:45-3:45 | Tabs 7 -> 8: archived usage, then original evaluated decision |
| 6. The safety check and value | 3:45-4:30 | Tabs 9 -> 8: synthetic missing-price replay, then original decision |

These are six recording scenes across the real tools, **not** the six pages of
the offline presentation. The [Mac guide](record-on-mac.md) still supplies
microphone, capture, trimming, and export instructions. Use this document for
the workflow narration instead of the archived deck's `narration.html`.

## 1. The toolkit and the gap, 0:00-0:50

**Click before speaking:**

1. Use **Command+1**. Confirm the introduction file says
   **From operating cost to coding decisions**.
2. Use **Shift+Command+5**. Confirm **Record Selected Portion**, microphone,
   save location, and the tested crop. Select **Record**.
3. After the countdown disappears, wait one quiet second. Read the first
   three paragraphs below, keeping the introduction visible.
4. Before "This demo uses synthetic historical cost data," use **Command+2**.
   Point to the original `"schema": SCHEMA` arguments at lines 156 and 165.
   Don't edit the code or switch the repository checkout.

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

**Next click:** Use **Command+3**.

## 2. The investigation, 0:50-1:35

**Click and point:**

1. In tab 3, point to the returned cost row and the warning saying June 2024
   history isn't current spend for the live resource group. This number is
   historical sample context, not experiment cost or savings.
2. Read the opening paragraph below. Don't look for an **Expand tool call**
   button: this is the original saved JSON response, not an MCP transcript.
3. Before "The original proposal had four bounded context tools," use
   **Command+4**. Point to the four tool names on the recorded proposal page.
   Keep this page visible for the rest of the section.

**Say:**

> First, the agent needs evidence, not just a prompt saying "make it cheaper."
> This is the original retained response from a bounded, read-only FinOps
> context adapter. I'm showing recorded evidence, not a live MCP call.
>
> The original proposal had four bounded context tools: cost summary, resource
> costs, cached recommendations, and applicable pricing.
>
> The opportunity comes from inspecting the code. Historical costs provide
> context; they don't prove this change will save money. That's why the next
> step is a specific proposal and a controlled measurement.

**Next click:** Use **Command+5**. Don't scroll through pages of JSON or run
a query to refresh it.

**Accuracy rule:** The four original context tools are PowerShell adapters,
not four tools on a newly built MCP server. The plugin separately configures
the read-only Azure MCP Kusto integration. Never fabricate a tool-call card or
describe a new review as the original session that produced the experiment.

## 3. The proposal, 1:35-2:05

**Show:** The [exact source comparison](https://github.com/bobjac/finops-toolkit/compare/c9df575ea8fa90cfec45072085d9919e21a12068...79a087dce14212ac6f47d090860001dbfa0fb47b),
focused on `agents.py`. Show both changed schema arguments.

**Click and point:**

1. In tab 5, point to the first red `"schema": SCHEMA` and its green
   replacement, which filters complete table definitions using
   `SCOPES[pattern]`.
2. At "These are the two changes," scroll just enough to point to the second
   replacement in the same file. Don't scroll through unrelated files.
3. Hold the diff while finishing the section. Don't select **Edit** or ask
   an agent to make another change.

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

**Next click:** Use **Command+6**.

## 4. The test, 2:05-2:45

**Click and point:**

1. In tab 6, confirm the **experiment** job is successful. This is the
   [original completed job](https://github.com/bobjac/finops-toolkit/actions/runs/43351201733/job/131642886198),
   not a workflow-dispatch form.
2. Point to **Build, deploy, load, collect, clean up, and compare**.
3. While discussing cleanup, point to **Always verify cleanup of only the
   selected run-owned temporary apps**.
4. Leave the completed steps visible. Don't select **Re-run jobs**,
   **Run workflow**, or any deployment action.

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

**Next click:** Use **Command+7**.
The cleanup claim here is about the experiment's temporary apps, **not**
full teardown of the retained sample or foundation.

## 5. The decision, 2:45-3:45

**Click and point:**

1. In tab 7, confirm the heading is **Azure usage, retained from the real
   measurement**. This file is `scene-2.html`, even though you're now in
   section 5 of the workflow.
2. Point to the three per-pass usage rows. Read the first paragraph below.
3. Before "The evaluator supplies the decision," use **Command+8**.
4. Point to **6.10%**, the baseline mean **1.2099**, and candidate **1.1361**.
   Then point to the quality, HTTP-error, price-coverage, and p95 columns
   while reading the rest. No calculation or button press is required.

**Say:**

> Application Insights captured the model usage. This is the retained usage
> table, not a live workbook. Each row is one pass: two baselines and one
> candidate. Each pass made 22 model calls. We compare per-pass cost rather
> than adding both baselines together.
>
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

**Next click:** Use **Command+9**, which selects the last tab in this
nine-tab recording window.

## 6. The safety check and value, 3:45-4:30

**Click and point:**

1. In tab 9, confirm **Synthetic missing-price case** is visible. This is
   `scene-5.html`. Point to **REPEAT**, not an Azure error screen.
2. Read the first paragraph below. Nothing needs to fail live.
3. Before "That's what we built," use **Command+8** to return to the
   original **ACCEPT** decision. Leave it visible for the closing paragraphs.

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

Review and export the saved movie using the Mac guide's
[review and trim](record-on-mac.md#5-review-and-trim) and
[export and submit](record-on-mac.md#6-export-and-submit) instructions.
Recording another take doesn't rerun the experiment.

## Optional MCP and workbook version

Skip this section for the click-by-click route above. It isn't another setup
task for the person recording. Don't replace the recorded-response narration
with live-tool claims without the matching verified screen.

For section 2, the assistant must first supply a genuine completed read-only
baseline review, the exact host conversation to reopen, and tested clicks to
expand its actual Azure MCP query and returned data. No such conversation
is supplied by the files above. A JSON response file isn't a tool-call card.
Label a new review `New read-only review of the original baseline.
Measured experiment completed November 13, 2026.`

Only with that real prepared screen, replace section 2's first paragraph with:

> First, the agent needs evidence, not just a prompt saying "make it cheaper."
> Here is a read-only Azure MCP query to the FinOps hub. This is synthetic
> historical cost context, not current application spend.

For section 5, the assistant must rehearse the
[actual workbook](https://portal.azure.com/#@/resource/subscriptions/6e87e78d-fe02-4f01-bd7b-4f2157eabd5a/resourceGroups/ftk-dto-hack-s-ae46/providers/Microsoft.Insights/workbooks/478410d0-a0ae-5679-89fe-eea6a576654c/workbook)
and stage its time and experiment filters before recording. Don't substitute
a portal sign-in page, expired-price total, or empty result. Only with the
verified workbook, replace section 5's first paragraph with:

> Application Insights captures model usage, and the workbook makes it visible
> alongside FinOps hub pricing. Here we can inspect consumption by agent and
> model. This view combines both baseline passes, so we use the evaluator's
> per-pass results for a fair comparison.

Keep the original evaluator comparison and historical-pricing disclosure in
either version.

## Assistant preparation checklist

This is work for the assistant/operator, not commands for the person recording.
It is **not** permission to rerun the experiment, grant roles, deploy, refresh
prices, or invoke the application.

1. For the default route, verify `workflow-map.html`, the four unchanged
   response copies, archive integrity, and the exact baseline, diff, and job
   links. The original context files come from the retained experiment inputs;
   don't regenerate them with today's queries. Don't switch the working tree
   to the baseline or alter the measured revisions.
2. Only for the optional MCP route, rehearse a bounded read-only review. Verify the
   configured Azure MCP Kusto connection and actual query access first.
   Capture a genuine successful call; stop on denied access rather than
   changing permissions or fabricating a response.
3. For that MCP example, use a labeled June 2024 synthetic historical cost query.
   Keep it separate from the recorded four-tool context handoff. Don't call
   stale recorded prices current, or imply this new query produced the old result.
4. If using a new review, finish the agent response off camera and supply
   tested reopening and expansion instructions. Label it a new read-only
   baseline review. Don't pass it off as original approval or measurement evidence.
5. Only for the optional workbook route, stage the actual workbook. Use **TimeRange**
   containing **November 13, 2026, 02:30-03:05 UTC**, **Baseline** `baseline`,
   **Candidate** `candidate`, and this exact **Experiment**:

   ```text
   ef560d02b1a2088bd8b25fe0bc55173d91d5ede2c2673e36a78978c99b79f400
   ```

6. For that workbook route, check rendering, data retention, filters, and
   privacy. If unavailable, keep the default recorded branch and its narration;
   don't improvise a false live demonstration.
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
