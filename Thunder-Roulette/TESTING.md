# Thunder Roulette v1.5 Manual Test Checklist

Use a disposable test profile where possible. Record failures with the selected
profile, BR limits, roll style, challenge reward/punishment, and the action that
triggered the problem.

## 1. Startup and profile migration

- [x] Launch from `Thunder-Roulette.ps1` without an error.
- [x] Existing profiles open without migration errors.
- [x] Existing profiles default to **Specific BR**.
- [x] The last selected profile is restored after restarting the app.
- [x] A previously rolled BR is restored for the selected profile.
- [x] Switching profiles immediately restores each profile's own BR result and roll style.
- [x] A newly created profile appears immediately in the main profile selector.

## 2. Specific BR rolls

- [x] Select **Specific BR** and limits `1.0-2.0`.
- [x] Roll four times and receive `1.0`, `1.3`, `1.7`, and `2.0` once each.
- [x] No BR repeats before all four valid stages are exhausted.
- [x] The next roll begins a fresh shuffled sequence.
- [x] Restart the app and confirm the current exact BR remains displayed.

## 3. Whole BR bracket rolls

- [x] Select **Whole BR bracket** and limits `1.0-3.7`.
- [x] Receive `1.0-1.7`, `2.0-2.7`, and `3.0-3.7` once each.
- [x] No bracket repeats before all valid brackets are exhausted.
- [x] Restart the app and confirm the current bracket remains displayed.
- [x] Switch away from the profile and back; confirm the bracket remains displayed.

## 4. Boundary clipping

- [x] Set limits to `1.3-3.3` in bracket mode.
- [x] Confirm the available brackets are exactly `1.3-1.7`, `2.0-2.7`, and `3.0-3.3`.
- [x] Confirm no displayed bracket exceeds the configured minimum or maximum.
- [x] Test a single-stage limit such as `2.3-2.3`; confirm it displays `2.3-2.3` without crashing.

## 5. BR reset and setting changes

- [x] **Reset BR sequence** clears the displayed BR to `—`.
- [x] Rolling afterward begins a fresh sequence.
- [x] Changing minimum or maximum BR clears the old displayed result.
- [x] Switching between Specific BR and Whole BR bracket clears the old result.
- [x] **Reset all** clears the BR display and queues but preserves profiles, history, custom content, and campaign progress.

## 6. BR challenge success and failure

- [x] In Specific BR mode, a successful BR challenge advances by the configured amount.
- [x] In Specific BR mode, **Go down one BR stage** moves down one valid exact stage.
- [x] In bracket mode, Success moves from `4.0-4.7` to `5.0-5.7`.
- [x] In bracket mode, **Go down one BR stage** moves from `5.0-5.7` to `4.0-4.7`.
- [x] A failure configured to stay keeps the current exact BR or bracket unchanged.
- [x] Failure at the minimum stays at the minimum and reports that it is already lowest.

## 7. Maximum BR completion

- [x] Advancing into the highest exact BR gives a normal advancement message and no completion animation.
- [x] Completing another challenge while already at the highest exact BR shows **CAMPAIGN COMPLETE**.
- [x] Advancing into the highest bracket gives a normal advancement message and no completion animation.
- [x] Completing another challenge while already at the highest bracket shows **CAMPAIGN COMPLETE**.
- [x] The completion banner fades in, remains briefly, fades out, and never crashes the session.
- [x] Success remains recorded after the banner animation.

## 8. Weapon and caliber progression

- [x] Success advances exactly one enabled weapon stage when configured.
- [x] Failure drops exactly one enabled weapon stage when configured.
- [x] Disabled stages are skipped.
- [x] Failure at the lowest stage stays at the lowest stage.
- [x] Advancing into the final caliber gives a normal advancement message and no completion animation.
- [x] Completing another challenge while already at the final caliber shows **CAMPAIGN COMPLETE**.

## 9. Session recording modes

- [x] **Detailed trackers** displays the configured counters and checkboxes.
- [x] Detailed Success remains disabled until all required targets are complete.
- [x] Counters can exceed their targets, for example `6 / 3`.
- [x] **Simple success / failed** hides trackers and enables both outcome buttons immediately.
- [x] Success and Failed clear the session note after recording the attempt.
- [x] Multiple attempts can be recorded without reopening the session window.
- [x] **End session** closes the window and creates one session-history entry.

## 10. History accuracy

- [x] Detailed history preserves actual over-target values such as `6 / 3`.
- [x] Each attempt shows its own outcome and note.
- [x] BR movement appears for BR-progression challenges only.
- [x] Weapon/caliber movement appears for weapon-progression challenges only.
- [x] A challenge with neither progression type shows neither BR nor Stage advancement fields.
- [x] Bracket advancement remains formatted as brackets in attempt history.
- [x] Session success/failure totals match the attempts shown.
- [x] Old history entries still open without `Unknown event` or missing-property errors.

## 11. Challenge editor and libraries

- [x] Create, edit, and delete a custom challenge.
- [x] Select both recording modes and confirm the saved selection persists.
- [x] Configure each Success reward type and Failure punishment type.
- [x] Reset challenge deck clears draw order without deleting custom challenges.
- [x] Restore challenges returns the shipped defaults.
- [x] Fun modes continue to draw without repeats and remain editable.

## 12. Release smoke test

- [x] Run source validation with:

  ```powershell
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Thunder-Roulette.ps1 -ValidateOnly
  ```

- [x] Build the executable with the Thunder Roulette icon.
- [x] Launch the packaged `Thunder-Roulette.exe` from a clean extracted folder.
- [x] Confirm the package contains no `Data`, profiles, history, `.git`, temporary files, or personal paths.
- [x] Confirm `README.md` instructs packaged users to launch `Thunder-Roulette.exe`.
- [x] Confirm the ZIP and executable versions agree on v1.5.0.
- [ ] Confirm the Git tag and release title agree on v1.5.0 when publishing.

Release-candidate evidence:

- ZIP: `dist/Thunder-Roulette-v1.5.0.zip`
- SHA-256: `994850A974EDC02296C2AD76EBFB5023DD036DF80B17E5023A419D6DC0286CCB`
- Package audit: 22 allowlisted files; no runtime data, source script, personal paths, or credential-like text.
- Clean extraction smoke launch: passed; the executable remained running and created fresh runtime data outside the ZIP.

## Release decision

- [x] All critical sections pass: Startup, BR rolls, progression, maximum completion, history, and packaged launch.
- [x] No known non-critical issues remain to document in the release notes.
- [x] Release candidate approved for v1.5.0.

Bottomnotes:
