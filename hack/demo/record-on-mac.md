# Record the demo on your Mac

Use your Mac's built-in **Screenshot** app to record and **QuickTime Player**
to review and trim. You don't need Windows, OBS, a webcam, or a paid recording
app. Record one browser window with your voice. Target **4 minutes 30 seconds**.

**Important:** The last verified evidence package wasn't recording-ready.
Its prices had expired, and recording materials and viewer checks were missing.
Creating this guide doesn't resolve those prerequisites. Complete the approved
[technical preparation](README.md) before the final rehearsal. Don't present
the historical 6.10% result as a fresh measurement.

These instructions use macOS Tahoe 26, Microsoft Edge or Google Chrome, and
the checkout used in this coding session. Some menu labels vary by version.
The instructions don't mean a native Mac recording has already been tested.

## Find your place

- [1. Choose your tools and check submission requirements](#1-choose-your-tools-and-check-submission-requirements)
- [2. Get the recording materials ready](#2-get-the-recording-materials-ready)
- [3. Check the package in Mac Terminal](#3-check-the-package-in-mac-terminal)
- [4. Arrange eight browser tabs](#4-arrange-eight-browser-tabs)
- [5. Prepare the workbook and source comparison](#5-prepare-the-workbook-and-source-comparison)
- [6. Prepare your microphone and screen](#6-prepare-your-microphone-and-screen)
- [7. Make a short test recording](#7-make-a-short-test-recording)
- [8. Rehearse once without recording](#8-rehearse-once-without-recording)
- [9. Start the final recording](#9-start-the-final-recording)
- [10. Follow the timed recording script](#10-follow-the-timed-recording-script)
- [11. Stop, save, and review](#11-stop-save-and-review)
- [12. Trim and export](#12-trim-and-export)
- [13. Submit and keep the confirmation](#13-submit-and-keep-the-confirmation)
- [Quick fixes](#quick-fixes)

## 1. Choose your tools and check submission requirements

Use these tools. PowerShell work belongs in the off-camera technical preparation,
not the recorded walkthrough.

| Tool | Purpose |
|---|---|
| Microsoft Edge or Google Chrome | Show the prepared answer, live workbook, proposal, source comparison, and decision |
| Terminal | Run local readiness checks and open the prepared views, off camera |
| Screenshot | Record a selected portion of the screen and your microphone |
| QuickTime Player | Play, trim, and export the recording locally |
| iMovie, only if needed | Produce an MP4 if the submission portal requires it |
| Paper, a phone, or a second display | Hold the narration outside the recorded area |

1. Open the **Microsoft PSA HTB Portal** using the organizer's actual link.
   Don't search for a look-alike sign-in page.
2. Sign in off camera and open your submission.
3. Check the allowed video formats, maximum file size, required attachments,
   and whether the portal accepts a file or a shared video link.
4. Confirm the deadline's **year, AM/PM, and timezone**. The organizer's email
   says November 27, 11:59 PT but doesn't specify AM/PM. Resolve that ambiguity
   before relying on it. Aim to submit a day early.
5. Write those requirements on your private checklist. Close the portal tab
   before recording.
6. In Finder, open **Documents**. Choose **File > New Folder**, name it
   `FinOps demo recording`, and open it.
7. Create two folders inside it: `Takes` and `Final`.
   Keep recordings in the approved private location, not the Git checkout.
   If Documents syncs to a service that isn't approved for these materials,
   use an approved local folder instead.

The private portal wasn't inspected for this guide. Its exact upload and
submission button names aren't verified; section 13 describes the actions
and confirmation you need rather than inventing those labels.

## 2. Get the recording materials ready

Do this before configuring the recorder. Don't record a deployment or experiment.

1. Complete [technical preparation sections 1-5](README.md#1-archive-clean-and-rebuild-off-camera).
   That includes the separately approved clean rehearsal, controlled measurement,
   access checks, opening-answer capture, screenshots, and evidence retention.
   Follow each section in order, not just the first linked section.
2. Obtain the actual **presentation output folder** from that preparation.
   It contains `index.html`, `preparation.json`, `comparison.json`,
   `experiment.json`, `negative.json`, `pricing.json`, `materials.json`,
   `manifest.json`, and the reviewed PNGs. Don't choose the input/originals folder.
3. Confirm that the preparation command exited **0** and the package says
   **Ready**, with no unresolved problems. Exit **2**, missing evidence, or
   **Not recording-ready** means stop.
4. Confirm that the off-camera clean rebuild and scoped cleanup receipts were
   accepted. A ready local package alone doesn't prove those operations happened.
5. Keep the approved originals, receipts, and presentation package together in
   private storage. Don't edit generated JSON, HTML, dates, or hashes.

**No new Azure work is authorized by these recording instructions.**
Don't dispatch workflows, grant permissions, refresh prices, run another paid
question, or delete resources to get past a failed check without the required
approval. The last retained package is not a substitute for a fresh ready one.

## 3. Check the package in Mac Terminal

All commands in this guide are for the Mac's **zsh** shell, not PowerShell.
Keep this Terminal window open until the recording is finished.

1. Use **Command+Space**, enter `Terminal`, and select **Return**.
2. Run this command to enter the checkout used in this session:

   ```bash
   cd "$HOME/work/src/github.com/microsoft/finops-toolkit/finops-toolkit"
   ```

3. Run `pwd`. Confirm that you're in the FinOps Toolkit repository.
   If the checkout moved, use its actual location before continuing.
4. Run this block. It asks for the presentation-folder path:

   ```bash
   PYTHON="$PWD/hack/sample-multi-agent-workload/.venv/bin/python"
   printf 'Paste the full presentation-folder path, then select Return: '
   IFS= read -r PRESENTATION
   ```

5. While Terminal waits, switch to Finder and select the presentation folder.
   Use **Option+Command+C** to copy its pathname. Switch back to Terminal,
   paste the path, and select **Return**. Paste only the path, without adding quotes.
6. Run these local checks:

   ```bash
   "$PYTHON" -m sample_workload.demo verify --directory "$PRESENTATION" &&
   "$PYTHON" -m sample_workload.demo show --directory "$PRESENTATION" --no-pause
   ```

7. Stop if either check fails. `verify` checks integrity; `show` additionally
   enforces recording readiness and current freshness. These commands don't
   contact Azure or invoke a model.
8. Read the actual decision, experiment hash, measurement start/end, and links
   in `preparation.json`. In Finder, right-click the file and choose
   **Open With > TextEdit** to read it. Don't save changes. Keep the exact
   experiment hash and measurement window on your private checklist.

The preparation and viewer checks expire after one hour, and prices and retention
must still be valid. If they expire, return to technical preparation for a new
verified export. Don't change a timestamp to bypass the check.

If the Python executable is missing, use the existing
[sample setup instructions](../sample-multi-agent-workload/README.md).
Don't substitute a different interpreter and assume the sample is installed.

## 4. Arrange eight browser tabs

Use a regular Edge or Chrome window already signed in to the correct Azure
and GitHub accounts. A new private window might not have the required access.
Sign in and complete any authentication prompts **before** recording.

1. Open Edge or Chrome. Use **Command+N** to create a dedicated window.
2. Return to the same Terminal window. Run the following block.
   It opens the local files and the **actual links from your package**.
   It doesn't send an application question. If you use Chrome, replace
   `Microsoft Edge` with `Google Chrome` in the block before running it.

   ```bash
   "$PYTHON" - "$PRESENTATION" <<'PY'
   import json
   from pathlib import Path
   import subprocess
   import sys

   folder = Path(sys.argv[1]).expanduser().resolve(strict=True)
   report = json.loads((folder / "preparation.json").read_text())
   if report.get("ready") is not True:
       raise SystemExit("Stop: this package is not recording-ready.")
   page = (folder / "index.html").as_uri()
   urls = [
       page + "#section-1",
       report["links"]["application"],
       report["links"]["workbook"],
       page + "#section-2",
       report["links"]["diff"],
       page + "#comparison",
       page + "#section-5",
       (folder / "manifest.json").as_uri(),
   ]
   subprocess.run(["open", "-a", "Microsoft Edge", *urls], check=True)
   PY
   ```

3. Return to the browser. Close any extra **New Tab** tab.
4. Arrange the eight tabs in the order below by dragging their tabs left or
   right. Opening links doesn't guarantee this order. If they opened in
   separate windows, drag the tabs into your dedicated window first.
5. Test each shortcut below. **Command+1** must show the answer, not another tab.
   Keep exactly these eight tabs in the recording window.

| Shortcut | What the tab must show |
|---|---|
| **Command+1** | Local evidence: **Previously captured application answer** |
| **Command+2** | Actual application `/docs` page |
| **Command+3** | Actual Azure workbook |
| **Command+4** | Local evidence: **Recorded proposal and context** |
| **Command+5** | Actual GitHub baseline-to-candidate source comparison |
| **Command+6** | Local evidence: **Original decision** and comparison table |
| **Command+7** | Local evidence: **Synthetic missing-price case** |
| **Command+8** | Local `manifest.json` |

The local evidence tabs have the same title. Identify them by the visible section,
not the title alone. If a link lands at the wrong position, use **Command+F**
to find the exact heading in the table, then **Escape** to close Find.

The application is an API, **not a chat website**. Tab 2 shows its documentation.
Don't select **Try it out**, **Execute**, or authentication controls. Don't
enter a token. Show the real, previously captured answer in tab 1 instead.

Opening the workbook makes normal read-only queries. It doesn't run the
controlled experiment again. Don't open the paid capture script on camera.

## 5. Prepare the workbook and source comparison

Get these views right now so the video doesn't become a search through menus.

1. Use **Command+3** to open the workbook. Wait for it to render.
2. Set **TimeRange** to a range containing **both baseline passes and the
   candidate pass** from `preparation.json`. If the portal offers an absolute
   custom range, use those times with a small margin. Otherwise choose a
   supported range, such as 7 days, only if it actually contains the measurement.
   Check whether the time picker displays local time or UTC.
3. Open **Experiment** and select the exact experiment hash on your checklist.
   Don't leave it on **All experiments**.
4. Keep **Baseline** as `baseline` and **Candidate** as `candidate`.
   Don't edit the hidden technical parameters or save workbook changes.
5. Locate **Usage and price coverage** and confirm that measured calls appear.
   Check **Unpriced or invalid usage** for missing prices or invalid usage.
   No measured calls is a blocker, not evidence of zero cost.
6. Locate **Agent and model breakdown**, **Estimated model cost by agent
   (USD, complete groups only)**, and **Tokens by model (cached input is
   included in input)**. Decide where to scroll during the video.
7. Use **Command+5**. On the GitHub comparison page, use **Command+F** to find
   `agents.py`, close Find with **Escape**, and locate the two schema-argument
   changes. Expand that file's diff if it is collapsed.
8. Use **Command+4** to inspect the proposal. Locate its context sources,
   original dates, and baseline/candidate revisions. Retain the original approval
   evidence privately; don't manufacture a new approval for the old experiment.
9. Use **Command+6**. Read the decision and all three measured rows.
   Scroll to **Original measured comparison** to locate answer counts,
   token totals, improvement, and baseline variation. Locate
   **Equivalent conditions and fixed guardrails** farther down.
10. Use **Command+7**. Confirm that the negative case is explicitly synthetic
    and reports incomplete evidence rather than a live missing-price incident.

If the workbook doesn't load, has empty results, or disagrees with the package,
stop and resolve it off camera. Don't substitute a screenshot while calling it
a live workbook. The workbook shows usage and prices; the evaluator, not the
workbook, supplies the quality checks and accept/reject/repeat decision.

## 6. Prepare your microphone and screen

Use headphones if they help you hear the test recording. A Mac microphone or
headset is enough; choose one and test it rather than changing inputs mid-take.

1. Connect your Mac to power. Close Mail, Teams, Messages, unrelated browser
   windows, password managers, and anything showing customer or personal data.
2. Open **System Settings > Sound > Input**. Select the microphone you intend
   to use. Speak normally and confirm that the input-level meter moves.
   Adjust the input volume if the device offers that control.
3. Close System Settings.
4. In the menu bar, open **Control Center > Focus > Do Not Disturb** and turn
   it on for the recording. Also silence nearby phones and watches.
5. Return to the dedicated browser window. Resize it to a wide landscape shape.
   Keep it in a normal window; don't use the green full-screen button.
6. Enlarge page text with **Command+Plus sign** until the answer and comparison
   table are readable without horizontal scrolling. Check all eight tabs.
   Local tabs might share a zoom level. Resize the window if necessary.
7. Plan to record only the browser's **page content**, below its tab bar and
   address bar. Leave out the Mac menu bar, Dock, account avatar, local file
   paths, and any unrelated identifiers. Keep the window in that exact position.
   Azure and GitHub can have account controls inside the page, too: place those
   outside the rectangle. Adjust each page's scroll position so headings and
   evidence remain inside the crop, not hidden above its top edge.
8. Put this script on paper, a phone, or a second display outside the recording
   rectangle. With one display, use paper or a phone; don't read it by switching
   the recorded browser to this guide.
9. Use **Command+1** and position the answer heading and relevant rows.

The local evidence includes JSON, not a polished chat UI. That's expected.
Show readable fields and describe them honestly. Don't edit generated pages
to make the recording look different: that breaks the integrity check.

## 7. Make a short test recording

This tests the actual microphone and captured area before the full take.

1. Use **Shift+Command+5** to open Screenshot.
2. Hover over the toolbar icons until the tooltip says **Record Selected Portion**.
   Select that icon. Don't select **Capture Selected Portion**, which takes a
   still image rather than a video.
3. Drag the selection's borders to enclose only the browser page content you
   planned in section 6. Prefer a wide rectangle. Don't include your script.
4. Select **Options**. Under **Save to**, choose **Other Location**, select
   your `FinOps demo recording/Takes` folder, and confirm the location.
5. Open **Options** again and select your actual microphone under **Microphone**.
   Don't leave it on **None**. The microphone records your voice; selecting
   the right input in Sound settings alone isn't enough.
6. Under **Timer**, choose **5 Seconds**. Enable **Show Mouse Clicks**.
   If your Mac offers a recording format choice, select
   **SDR (Most Compatible)**. System audio isn't needed for this narrated demo.
7. Select **Record**, wait for the countdown, and say:
   "This is my FinOps demo microphone test. The answer and the cost comparison
   should be readable."
8. Use **Command+6**, point to a comparison row, then briefly show tabs 3 and 5
   to check their framing and account controls.
9. After about 20 seconds, use **Control+Command+Escape** to stop.
   The stop-recording button in the Mac menu bar is the alternative.
10. Wait for the floating thumbnail to disappear so the file saves.
11. In Finder, open `Takes`. Right-click the new
    `Screen Recording [date] at [time].mov` file and choose
    **Open With > QuickTime Player**.
12. Play the entire test with **Spacebar**. Check your voice, readable figures,
    crop boundaries, cursor, and absence of notifications or private details.

If macOS asks for a recording or microphone permission, stop and handle the
prompt off camera. Follow the prompt into **System Settings > Privacy &
Security** if needed, allow only the app you're using, and reopen it if asked.
Then repeat the test. Don't assume a silent or blank test will fix itself.

Rename the test file `microphone-and-screen-test.mov` in Finder so you won't
mistake it for the final take. No application question or model call is needed
for this test.

## 8. Rehearse once without recording

Read section 10 aloud while switching through the eight prepared tabs.

1. Put a timer on your phone outside the recording area.
2. Start at tab 1 and follow the six scenes. Aim for 4:30, not a rushed 5:00.
3. Practice switching tabs using the shortcuts. Scroll slowly and stop while
   speaking about a number. Don't continuously move the cursor.
4. For scene 4, choose **one** outcome paragraph matching the actual decision.
   Write its exact numbers on your private script. Don't default to Accept.
5. Confirm that your narration matches the dates and labels on screen.
   Rehearsing the recording doesn't create a new measurement.
6. If you exceed five minutes, shorten the narration and rehearse again.
   Don't remove evidence limitations to make room.
7. Return to tab 1 and reset its scroll position.

## 9. Start the final recording

Don't start if any required live or privacy check is unresolved.

1. Return to Terminal, outside the intended recording area. Rerun the two
   checks from section 3:

   ```bash
   "$PYTHON" -m sample_workload.demo verify --directory "$PRESENTATION" &&
   "$PYTHON" -m sample_workload.demo show --directory "$PRESENTATION" --no-pause
   ```

2. If they succeed, return to the browser. Confirm that the live workbook is
   still rendered with the correct experiment and time range.
3. Use **Command+1**. Confirm the opening answer is positioned correctly.
4. Use **Shift+Command+5**. Confirm **Record Selected Portion**, the rectangle,
   `Takes` save location, microphone, and five-second timer are still selected.
5. Select **Record**. Put your hands in position during the countdown.
6. After the countdown disappears, wait one quiet second and begin scene 1.

Record one continuous take. Don't rely on a native pause/resume button.
If you make a substantial mistake, stop, reset the tabs, and record another take.
A recording retake doesn't require rerunning the experiment or sending another
question. Recheck readiness if the package expires between takes.

## 10. Follow the timed recording script

Keep the narration outside the captured area. The times are targets, not
automatic scene changes.

### Scene 1: Show the answer, 0:00-0:35

1. Stay in **tab 1**. Show the question, returned inventory rows, capture date,
   trace, and four-agent usage evidence. Scroll only enough to make them readable.
2. Point to the products below their reorder points.
3. Read:

> An AI assistant can give the right answer and still use more context than it
> needs. In this synthetic retail example, several agents cooperate to identify
> products below their reorder point. This is a previously captured real Azure
> OpenAI response. I'm not sending another question or running a new experiment
> during this video.

### Scene 2: Show the Microsoft components, 0:35-1:15

1. Use **Command+2**. Show the actual API documentation for about five seconds.
   Don't invoke an endpoint.
2. Use **Command+3**. Show the selected experiment and time range.
   Scroll to the usage and agent/model panels.
3. Use **Command+6**, then **Command+F** to find **Pricing with original dates**.
   Close Find with **Escape** and show the retained price dates.
4. Read while showing those views:

> The sample runs on Azure Container Apps with Azure OpenAI. Application
> Insights captures correlated model usage, and the FinOps hub in Azure Data
> Explorer supplies public-retail pricing. The workbook connects those views.
> The experiment fixes the data, model, seven questions, pacing, and evaluation
> rules, then measures the baseline twice before measuring the candidate.

### Scene 3: Show the bounded change, 1:15-2:05

1. Use **Command+4**. Show the recorded proposal's four context sources and dates.
2. Use **Command+5**. Show the two schema-argument changes in `agents.py`.
3. Read:

> The design-time optimizer uses four bounded, read-only context tools:
> cost summary, resource costs, cached recommendations, and current pricing.
> The proposal is to send each specialist only the complete table definitions
> approved for that question. Both schema arguments change. The model, data,
> agent call topology, measurement, and guardrails stay fixed.
>
> This recorded proposal predates the measurement. Publication, deployment,
> paid traffic, and cleanup have separate human approvals. The agent doesn't
> autonomously change production.

Don't open a new coding-agent session during this take or describe a new
proposal as the origin of the completed experiment.

### Scene 4: Show the actual decision, 2:05-3:10

1. Use **Command+6**, then **Command+F** to find **Original decision**.
   Close Find with **Escape**. Show the comparison table and its two baseline
   rows plus candidate row.
2. Point to unit cost, quality, errors, price coverage, and p95.
   Scroll to **Original measured comparison** for answer/token counts and
   baseline variation, then the fixed guardrails.
3. Read this common explanation:

> The denominator is successful evaluated answers, not model calls. All
> measured consumption stays in the numerator, including nonanswers or failures.
> We require 100 percent answer quality, zero HTTP errors, complete applicable
> prices, and no more than 20 percent p95 latency regression. An accepted cost
> improvement must exceed both five percent and the observed baseline spread.

4. Read **only the matching paragraph** below, adding the exact values from
   your current package:

| Decision on screen | What to say |
|---|---|
| **Accept** | "The candidate passed those checks. Baseline mean cost is [read value] and candidate cost is [read value] US dollars per 1,000 successful evaluated answers, an improvement of [read percentage]. These are public-retail model-only estimates, not invoice savings or a statistically powered benchmark." |
| **Reject** | "The candidate was rejected because [read the actual reason]. Finding an unsafe or more expensive change before adoption is useful. I'm not claiming savings." |
| **Repeat** | "The result is repeat because [read the actual reason]. The evidence doesn't support accepting this change yet. I'm not claiming savings." |

**Incomplete primary evidence means stop**, even if a historical result exists.
The deliberately incomplete synthetic case in scene 5 is separate.

### Scene 5: Show the negative case, 3:10-3:45

1. Use **Command+7**. Show the **Synthetic missing-price case** heading and result.
2. Read:

> This is a synthetic negative test using an isolated copy of the retained
> measurement. We remove the output-token meter and run the unchanged evaluator
> at the original evaluation time, without changing price dates. The result is
> repeat with incomplete evidence. Unknown cost doesn't become zero. No live
> price, deployed app, or original decision was changed.

### Scene 6: Explain reuse and limits, 3:45-4:30

1. Use **Command+8**. Show the manifest's evidence filenames and hashes.
   Hashes establish local integrity, not an independent signature.
2. Read:

> A partner can reuse the standalone sample, bounded context adapters,
> protected experiment, evaluator, and evidence handoff with another approved
> workload. The value is a traceable design-time decision, including reasons to
> reject or repeat.
>
> These estimates exclude infrastructure, telemetry, builds, and warm-up.
> Resources retained for recording remain billable until their separately
> approved teardown. This demonstrates a working proof of concept, not a
> production-ready autonomous optimizer.

3. Return to **tab 6**. Use **Command+F** to find **Original decision**, close
   Find with **Escape**, and leave the decision table as the final frame.
4. Finish speaking and wait two quiet seconds.

Don't claim cleanup or a clean rebuild succeeded unless its actual receipts
verify that claim. Keep the original pricing dates visible when discussing
pricing; those dates are in **Pricing with original dates** in the local page.

## 11. Stop, save, and review

Use the saved movie, not memory of the take, to decide whether it's usable.

1. Use **Control+Command+Escape** to stop recording.
2. Wait for the floating thumbnail to disappear and the file to save.
3. In Finder, open `Takes`. Select the newest recording and use **Return**
   to rename it `finops-demo-take-01.mov`. Keep the `.mov` extension.
   Use `take-02`, `take-03`, and so on for later attempts.
4. Right-click the file and choose **Open With > QuickTime Player**.
5. Play the whole recording with headphones or speakers at a normal volume.
   Check all of the following:

| Check | Passing result |
|---|---|
| Duration | 3-5 minutes, including the opening and closing |
| Audio | Narration is audible throughout, without clipping or long gaps |
| Readability | Products, decision, unit-cost values, and labels are legible |
| Evidence | Selected experiment and outcome match the package |
| Honesty | Previously captured answer, model-only estimates, and synthetic negative case are labeled |
| Privacy | No tokens, personal/customer content, account menus, notifications, or unrelated identifiers |
| Capture | Correct crop throughout; no Terminal, script, permission prompt, or blank scene |

If the crop or audio is wrong throughout, make a new take. Trimming won't fix it.
If a credential appears, don't upload that take or send it to an online editor.
Handle the exposure through the approved credential-response process and make
a clean replacement recording.

## 12. Trim and export

Keep the original take. Edit and export a separate copy.

1. In Finder, select the chosen take and use **Command+D** to duplicate it.
2. Rename the duplicate `finops-demo-edit.mov` and open it in QuickTime Player.
3. Choose **Edit > Trim**.
4. Drag the yellow handles to remove only unwanted silence at the beginning
   and end. Keep the full explanation and evidence limitations.
5. Select **Trim**. Save the edited copy with **Command+S**.
6. Choose **File > Export As > 1080p** if that option is available.
   Choose **Greater Compatibility (H.264)** in the export format control
   if offered. Don't upscale an unreadable small capture and expect more detail.
7. Save the export in `Final` as `finops-design-time-optimizer-demo.mov`.
8. Open that exported file and play it from beginning to end again.
   Confirm duration, audio, text, privacy, and outcome after export.
9. In Finder, select the final file and use **Command+I** to check its size
   against the portal's actual limit.

QuickTime export produces a **MOV**, not an MP4. **Don't rename `.mov` to
`.mp4`**. If the portal accepts your MOV and size, skip the next procedure.

### Make an MP4 only if required

Use iMovie locally. If it isn't installed, obtain Apple's iMovie from the
Mac App Store before continuing. Don't upload the recording to a web converter.

1. Open iMovie. In the Projects view, choose **Create New > Movie**.
2. Choose **File > Import Media**, select your edited movie, and import it.
3. Drag the imported clip into the empty timeline. Don't add a theme,
   background music, titles, or transitions.
4. Choose **File > Share > File**. If your version shows **Export File**
   under the Share button instead, use that local-file option.
5. Set **Format** to **Video and Audio**, **Resolution** to **1080p** when
   available, and **Quality** to **High**. Don't select **Best (ProRes)**,
   which produces a different, much larger export.
6. Select **Next**, choose `Final`, and save as
   `finops-design-time-optimizer-demo.mp4`. Wait for export to finish.
7. Check the actual extension in Finder. Open the MP4 in QuickTime and watch
   the full exported file. Confirm its size and 3-5-minute duration again.

An export option can depend on the input's resolution and your app version.
If the file is too large, use an allowed lower export resolution only if the
numbers remain readable. Otherwise improve the framing and record another take.
Don't remove evidence or speed up narration just to fit a file-size limit.

## 13. Submit and keep the confirmation

The recording is finished only after you have a playable final export.
Submission is a separate human step.

1. Back up the final video, selected original take, presentation package,
   originals, and rehearsal/cleanup receipts to the approved private retention
   location. Confirm that the copied video and package open.
2. Keep a private rehearsal record with the exact source revision, experiment
   and workflow IDs, pricing date, viewer check, workbook window, package hash,
   duration, and audio/privacy review. Include failed attempts and limitations.
   Use the [technical runbook's evidence checklist](README.md#7-save-the-rehearsal-record-and-submit).
3. Reopen the organizer's actual portal link. Sign in and open your submission.
4. Use its video-upload action to select the **final reviewed file** in `Final`,
   not the microphone test, an old take, or the evidence JSON.
5. If the portal requires a shared link instead, upload only to the approved
   destination. Set the required viewer permissions and verify access as the
   intended reviewer, not just as the file owner.
6. Add the other required materials. Match every claim to the recorded evidence.
7. Wait for upload and any processing to finish. Preview the uploaded video
   if the portal offers playback.
8. Complete the portal's final submission action. Verify a confirmation or a
   submitted status; a saved draft or an upload progress bar isn't confirmation.
9. Keep the confirmation privately beside your final video. Don't post personal
   portal details or submission receipts in a public GitHub issue.
10. Request acceptance and closure of
    [issue #14](https://github.com/bobjac/finops-toolkit/issues/14) only after its
    remaining requirements are verified. Don't close it just because the guide
    or video exists.
11. Arrange final Sample and Foundation teardown under separate explicit
    approvals. Verify the cleanup receipts and preserve the evidence.
    Recording, tags, budgets, and resource expiry labels don't stop billing.

## Quick fixes

| Problem | What to do |
|---|---|
| Screenshot shows **Capture**, not **Record** | Select **Record Selected Portion**, the video icon, not the still-image icon |
| No voice in the test | Reopen Screenshot **Options > Microphone**, select the actual input, and record another test |
| You can't find the recording | Check Screenshot **Options > Save to** and open that exact folder in Finder |
| Wrong view for **Command+1** | Close extra tabs and drag the eight demo tabs into the documented order |
| Workbook is empty | Stop; check experiment, time range, access, and real telemetry off camera |
| Package expires | Return to approved technical preparation; don't edit dates or hashes |
| You make a speaking mistake | Stop and make another take using the same evidence while it remains ready |
| You need an MP4 | Export with iMovie; changing a MOV filename doesn't convert it |
| You want to stop immediately | Use **Control+Command+Escape** |

## Apple reference instructions

These are references for macOS controls, not additional demo prerequisites.

- [Record the screen on your Mac](https://support.apple.com/en-us/102618)
- [Trim a movie in QuickTime Player](https://support.apple.com/guide/quicktime-player/trim-a-movie-or-clip-qtpf2115f6fd/mac)
- [Export movies in QuickTime Player](https://support.apple.com/guide/quicktime-player/export-movies-qtp20e395859/mac)
- [Export a file from iMovie](https://support.apple.com/guide/imovie/export-a-movie-trailer-or-clip-as-a-file-ibrw3910e1ca/mac)
