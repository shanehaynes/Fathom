# Fathom (working name) — a two-phase alarm clock for iOS

A Loftie-style wake: a gentle 30-second sound, a chosen gap, then a firmer phase that escalates and holds. Design in [DESIGN.md](DESIGN.md); visual reference in [prototype/design-prototype.html](prototype/design-prototype.html).

## Status: milestone 1 — walking skeleton

This is the go/no-go build from DESIGN.md §8: a bare test bench that arms a real AlarmKit chain on your phone so the reliability matrix (§9) can be run before any real UI exists. **Written on Linux without compiling** — expect a round of compiler fixes in Xcode; the structure is right, the surface may need adjusting.

## Build (on the Mac)

Requires Xcode 26+ and an iPhone on iOS 26+ (AlarmKit needs a physical device for the Silent-switch and Focus tests).

```bash
brew install xcodegen
git clone https://github.com/shanehaynes/alarm-clock.git && cd alarm-clock
xcodegen generate
open Fathom.xcodeproj
```

In Xcode:
1. Select the `Fathom` target → Signing & Capabilities → set your Team (do the same for `FathomWidgets`). Optionally paste the team ID into `DEVELOPMENT_TEAM` in `project.yml` so regeneration keeps it.
2. Pick your iPhone as the run destination and run. Accept the AlarmKit permission prompt.

If the project drifts, edit `project.yml` and re-run `xcodegen generate` — the `.xcodeproj` is generated and git-ignored.

## Layout

```
project.yml                       XcodeGen spec (app + Live Activity extension)
Fathom/App/                       App entry + milestone-1 test bench view
Fathom/Alarm/ChainPlan.swift      Pure timing spec of a chain (DESIGN.md §3) — no AlarmKit
Fathom/Alarm/ChainScheduler.swift Turns a plan into AlarmKit system alarms; logs results
Fathom/Alarm/ChainStore.swift     chainID → alarm IDs, so any dismissal can cancel siblings
Fathom/Alarm/ImUpIntent.swift     The stopIntent on every alarm: "I'm up" cancels the chain
Fathom/Alarm/WakeMetadata.swift   Per-alarm metadata (shared with the widget target)
Fathom/Resources/Sounds/          Placeholder 30 s WAVs (phase1_gentle, phase2_a…e)
FathomWidgets/                    Minimal Live Activity for lock screen / Dynamic Island
tools/gen_placeholder_sounds.py   Regenerates the placeholder sounds (stdlib only)
```

## Milestone-1 test protocol

Use the test bench: "Phase 1 in 2 min", gap "1 min (test)", plateau repeats 4 → 10 alarms, last fires ~10 minutes out. Then, one row at a time from DESIGN.md §9:

| # | Set up | Expect |
|---|---|---|
| 1 | Silent switch on | Every step audible; full-screen alert with "I'm up" |
| 2 | Sleep Focus on | Same |
| 3 | Arm, then force-quit the app | Chain still fires; tapping "I'm up" cancels the rest (check "Armed alarms" after relaunch → empty) |
| 4 | Arm with phase 1 ≥ 5 min out, restart the phone, leave it locked | Chain fires |
| 8 | Tap "I'm up" on phase 1 | No phase-2 alarm ever fires — this is the core mechanic |
| 7 | Arm, then "Cancel everything" | Nothing fires |

Things to confirm on-device that docs don't settle (record the answers in DESIGN.md §3/§7):
- Does a custom `.wav` from the bundle play, or only `.caf`? (If only `.caf`: `afconvert -f caff -d LEI16 in.wav out.caf` and update `ChainPlan.escalationFiles`.)
- Does an alarm's sound loop until dismissed, or play once? This decides whether the plateau needs the repeat alarms at all.
- What happens to an alerting alarm when the next chain member fires 45 s later?
- Does the system alert appear without the Live Activity extension? (If yes, the extension can be dropped until milestone 2.)

## Next

Milestone 2 — port the prototype's scene (DESIGN.md §5 constants) to SwiftUI `Canvas`.
