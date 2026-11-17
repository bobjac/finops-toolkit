# Record the completed experiment on your Mac

**The experiment is already done. You don't need to run it again.**
The assistant prepares and checks the archived presentation. Your job is to
record its six scenes and your narration, review the video, and submit it.
You don't need Terminal, PowerShell, Azure commands, or a new model request.

**For the workflow-led demo, use the [rewritten demo script](workflow-script.md).**
It shows the coding agent investigating, proposing a narrow change, and using
the completed experiment to reach a decision. Its additional agent/MCP and
workbook views still need an assistant-led read-only rehearsal.
The six-page presentation and `narration.html` below remain the offline fallback.
Use this page's microphone, capture, trimming, and export steps for either version.

The presentation is an **archived walkthrough of a real completed experiment**.
It isn't a new live run or a current-price quote. The original response text
wasn't retained, so the opening shows actual evaluation metadata, not a
reconstructed chat answer. The usage scene is archived data, not a live workbook.

The earlier version of this guide mixed technical rehearsal requirements with
recording. Those instructions are now in the separate
[fresh live recording guide](record-live-on-mac.md). Don't follow that guide
just to record the archived result.

## What you'll use

| Tool | Purpose |
|---|---|
| Microsoft Edge or Google Chrome | Show the prepared six-scene presentation |
| Screenshot, built into macOS | Record the browser page and your microphone |
| QuickTime Player, built into macOS | Review, trim, and export your recording |
| iMovie, only if required | Convert the edited movie to MP4 locally |
| Paper, a phone, or a second display | Read the prepared narration outside the recording area |

Target **4 minutes 30 seconds**. No webcam, Windows device, or paid recording app
is required. These instructions use macOS Tahoe 26; some labels vary by version.

## Find your place

- [1. Open the prepared presentation](#1-open-the-prepared-presentation)
- [2. Prepare your microphone and screen](#2-prepare-your-microphone-and-screen)
- [3. Make a short recording test](#3-make-a-short-recording-test)
- [4. Record the six scenes](#4-record-the-six-scenes)
- [5. Review and trim](#5-review-and-trim)
- [6. Export and submit](#6-export-and-submit)

## 1. Open the prepared presentation

The assistant supplies the actual local folder and opens the checked presentation.
Don't download the source repository and try to build a presentation yourself.

1. Open **Finder** and use **Shift+Command+G**. Paste this saved folder path,
   then select **Return**:

   ```text
   ~/Movies/FinOps demo/Archived experiment 43351201733
   ```

2. Double-click **index.html**. If it opens in an editor, right-click it and
   choose **Open With > Microsoft Edge** or **Google Chrome**. Its first
   scene says **A completed experiment, not another run**. This works after
   a reboot; it doesn't depend on a window previously opened by the assistant.
3. Select **Next scene** at the bottom. Confirm you can move through all six
   scenes. On scene 6, select **Start again** to return to the beginning.
4. Open **narration.html** from the same folder, off camera. It contains the
   complete timed script with the actual archived figures already filled in.
   Read it from a second display, or use **Command+P** to print it. Don't put
   the narration inside the part of the screen you're recording.
5. Return to the presentation's first scene. Keep the entire folder together;
   the other scenes are local HTML files linked from `index.html`.

No Azure sign-in, application request, live workbook, or source-code editing
is required. Don't change the generated presentation or its original dates.
The assistant handles evidence checks; you don't need to interpret JSON.

## 2. Prepare your microphone and screen

Do this off camera. There's no need to change your Mac's normal browser profile.

1. Connect the Mac to power and choose a quiet place.
2. Close Mail, Teams, Messages, unrelated browser tabs, and windows containing
   customer or personal data. Silence your phone and watch.
3. Open **System Settings > Sound > Input**. Select your Mac microphone or
   headset. Speak and confirm that the input-level meter moves.
4. Close System Settings.
5. Open **Control Center > Focus > Do Not Disturb** from the menu bar and
   turn it on for the recording.
6. Put the presentation in one normal browser window. Don't use the green
   full-screen button. Make the window wide enough to show the tables.
7. Check that the first scene and its **Next scene** button fit on screen.
   Use **Command+Plus sign** to enlarge text or **Command+Minus sign** to
   reduce it if necessary. Readability matters more than filling every pixel.
8. Leave your script on paper or a second display outside the captured area.
   On one display, use paper rather than switching the recorded browser
   between the presentation and narration.
9. In Finder, create a private recording folder with two subfolders:
   **Takes** and **Final**. Use an approved local location; don't put video
   files in the Git repository or an unapproved synced folder.

## 3. Make a short recording test

This tests the actual capture settings before the full take.

1. Return to the presentation's first scene.
2. Use **Shift+Command+5** to open Screenshot.
3. Hover over the toolbar icons and select **Record Selected Portion**.
   Don't select **Capture Selected Portion**, which takes a still image.
4. Drag the selection borders around the browser's page content, including
   the scene heading and navigation. Exclude the address bar, tabs, Mac menu
   bar, Dock, local file path, and your narration.
5. Select **Options > Save to > Other Location** and choose your **Takes**
   folder. Confirm the location.
6. Open **Options** again. Under **Microphone**, select the actual microphone
   you tested. Don't leave it on **None**.
7. Set **Timer** to **5 Seconds** and enable **Show Mouse Clicks**.
   If a recording format choice appears, use **SDR (Most Compatible)**.
   You don't need system audio for this voice-only demo.
8. Select **Record**. After the countdown, say:
   "This is my FinOps recording test. My voice and the figures should be clear."
9. Select **Next scene** a few times to check navigation and framing.
10. After about 20 seconds, use **Control+Command+Escape** to stop.
    The stop-recording button in the menu bar is the alternative.
11. Wait for the floating thumbnail to disappear so the movie saves.
12. In Finder, open **Takes**. Right-click the newest
    `Screen Recording [date] at [time].mov` file and choose
    **Open With > QuickTime Player**.
13. Play the entire test with **Spacebar**. Check your voice, readable text,
    crop boundaries, and absence of private information.

If macOS asks for microphone or recording permission, handle the prompt off
camera and repeat the test. Follow its System Settings instructions, allowing
only the app you're using. A silent test isn't a usable recording.

Rename the test file `microphone-and-screen-test.mov` so it can't be mistaken
for your final video.

## 4. Record the six scenes

This section is for the offline fallback. For the workflow-led version, follow
the [workflow script's screen order and narration](workflow-script.md#screen-order)
instead; don't read the deck's older `narration.html` over different screens.

Read **narration.html** aloud once before recording. It is the complete script;
the table below tells you when to move to the next scene. If the rehearsal
exceeds five minutes, shorten pauses rather than omitting the limitations.

| Time | Show | Talk about |
|---|---|---|
| 0:00-0:35 | Scene 1: completed experiment | Real retained inventory evaluation; no recreated answer or new request |
| 0:35-1:15 | Scene 2: Azure usage | Microsoft components and actual archived token/call counts |
| 1:15-2:05 | Scene 3: bounded proposal | Four read-only context tools, narrowed schemas, unchanged guardrails |
| 2:05-3:10 | Scene 4: original decision | Actual baseline/candidate costs, quality, coverage, errors, and limitations |
| 3:10-3:45 | Scene 5: missing-price test | Isolated synthetic replay; unknown cost isn't zero |
| 3:45-4:30 | Scene 6: evidence and limits | Original dates, reusable components, model-only estimates, cleanup boundaries |

1. Return to scene 1 with **Start again**.
2. Use **Shift+Command+5**. Confirm **Record Selected Portion**, the rectangle,
   **Takes** location, microphone, and five-second timer.
3. Select **Record**. After the countdown disappears, wait one quiet second.
4. Read the script for scene 1. Select **Next scene** when you're ready for
   scene 2, and continue through the six scenes.
5. Speak at a comfortable pace. Point to a number, then hold the cursor still.
   Don't open external links, run commands, or switch to Azure.
6. On scene 6, finish speaking and wait two quiet seconds.
7. Use **Control+Command+Escape** to stop.
8. Wait for the file to save. Rename it in Finder to
   `finops-demo-take-01.mov`, keeping the `.mov` extension.

If you make a substantial mistake, stop and start another take. Use `take-02`,
`take-03`, and so on. Recording another take does **not** rerun the experiment.
Don't claim the archived result is a current-price measurement, and don't
describe the synthetic negative case as a live failure.

## 5. Review and trim

Review the actual saved file, not just how the take felt.

1. Open the chosen take with **Open With > QuickTime Player**.
2. Play it from beginning to end. Confirm a **3-5-minute** duration, clear voice,
   readable figures, correct scene order, and no credentials, personal/customer
   information, notifications, or narration inside the captured area.
3. If the audio or crop is wrong throughout, record another take. Trimming
   won't repair those problems. Don't upload a take exposing a credential.
4. Keep the original take. In Finder, select it and use **Command+D** to
   duplicate it. Rename the duplicate `finops-demo-edit.mov`.
5. Open the duplicate in QuickTime Player and choose **Edit > Trim**.
6. Drag the yellow handles to remove unwanted silence at the beginning and
   end. Keep the archived-evidence labels and limitations.
7. Select **Trim**, then save the edited copy with **Command+S**.

## 6. Export and submit

Check the organizer's actual portal requirements before choosing the final format.
The private portal's button names haven't been verified for this guide.

1. In QuickTime, choose **File > Export As > 1080p** if available.
   Use **Greater Compatibility (H.264)** if that choice is offered.
2. Save in **Final** as `finops-design-time-optimizer-demo.mov`.
   QuickTime exports MOV; renaming `.mov` to `.mp4` doesn't convert it.
3. If the portal requires MP4, open iMovie and choose **Create New > Movie**.
   Use **File > Import Media**, select the edited movie, and drag it into
   the empty timeline. Don't add a theme or background music.
4. Choose **File > Share > File**, or **Export File** under the Share button
   if your version uses that label. Set **Video and Audio**, **1080p** when
   available, and **High** quality, not **Best (ProRes)**.
5. Select **Next** and save `finops-design-time-optimizer-demo.mp4` in **Final**.
   Wait for export to finish. Skip steps 3-5 if MOV is accepted.
6. Open the final export in QuickTime and watch it all the way through again.
   Confirm 3-5 minutes, readable figures, audible narration, privacy, and honest
   labels. In Finder, use **Command+I** to check the file-size limit.
7. Open the organizer's actual **Microsoft PSA HTB Portal** link and sign in
   off camera. Verify the deadline's year, AM/PM, timezone, required files,
   accepted formats, and size limit. The email's November 27, 11:59 PT
   wording doesn't specify AM/PM; resolve that ambiguity.
8. Upload the reviewed file from **Final**, not the microphone test or an
   earlier take. If a link is required instead, use the approved hosting
   destination and verify that the intended reviewers can view it.
9. Wait for upload/processing and preview the uploaded video if offered.
   Complete the portal's submission action and verify confirmation or a
   submitted status. A saved draft isn't a submitted entry.
10. Keep the final video, presentation folder, original take, and confirmation
    in approved private storage. Don't publish personal submission receipts.

**Separate operational work:** Recording this archived walkthrough doesn't close
[issue #14](https://github.com/bobjac/finops-toolkit/issues/14), attest to a new
clean rebuild, or tear down Azure. The assistant can handle those operations
under their separate approvals. They aren't commands you need to execute to
record this presentation.

## Quick fixes

| Problem | What to do |
|---|---|
| The old guide tells you to run PowerShell | Use this archived recording guide, not the separate fresh live guide |
| You can't find the presentation | Use the actual folder supplied by the assistant; its start file is `index.html` |
| A scene is too large | Widen the browser or reduce page zoom, then repeat the short test |
| Screenshot shows **Capture**, not **Record** | Select **Record Selected Portion**, the video icon |
| No recorded voice | Set Screenshot **Options > Microphone** to the correct input and test again |
| You need to stop immediately | Use **Control+Command+Escape** |
| You make a speaking mistake | Stop and record another take; no experiment rerun is needed |
| The portal requires MP4 | Export through iMovie; don't rename the MOV extension |

## Apple reference instructions

- [Record the screen on your Mac](https://support.apple.com/en-us/102618)
- [Trim in QuickTime Player](https://support.apple.com/guide/quicktime-player/trim-a-movie-or-clip-qtpf2115f6fd/mac)
- [Export from QuickTime Player](https://support.apple.com/guide/quicktime-player/export-movies-qtp20e395859/mac)
- [Export from iMovie](https://support.apple.com/guide/imovie/export-a-movie-trailer-or-clip-as-a-file-ibrw3910e1ca/mac)
