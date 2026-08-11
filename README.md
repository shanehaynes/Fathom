# Fathom

A two-phase alarm clock for iOS. The full spec is [DESIGN.md](DESIGN.md); the visual
reference is [prototype/design-prototype.html](prototype/design-prototype.html).

Gentle sound, a gap you chose the night before, then a firm escalation. No snooze,
no accounts, no daytime destination. The interface speaks only warm white; the
water owns every other color.

## Building

Requires **Xcode 26+** (AlarmKit, iOS 26 deployment target) on macOS. The project
file is generated:

```
brew install xcodegen   # once
xcodegen generate
open Fathom.xcodeproj
```

Placeholder sounds are checked in under `Fathom/Resources/Sounds/`. To regenerate
them: `python3 scripts/make_placeholder_sounds.py` (no dependencies; uses the
system `afconvert`).

Set your development team in Signing & Capabilities, then run on a device.
AlarmKit behavior cannot be trusted from the simulator — milestone 1 is a
device exercise by definition.

## Layout

| Path | Contents |
|---|---|
| `Fathom/Scene/` | §5 visual system — Canvas port of the prototype, constants verbatim |
| `Fathom/Models/` | Alarm model, sound pairs, chain timing (§3), state machine |
| `Fathom/Alarms/` | AlarmKit chain expansion, dismiss intent, backup notification chain |
| `Fathom/Audio/` | Wake handoff ramp, wind-down fade, pair previews (§7) |
| `Fathom/Screens/` | Tonight, Alarm, Wake — three screens, there is no fourth (§4) |
| `Fathom/Store/` | Single local JSON store (§7 — decided over SwiftData; the model is tiny) |
| `scripts/` | Placeholder sound synthesis |

## Implementation decisions on top of DESIGN.md

- **Fixed-date chains.** Chain offsets need second-level precision (B at +0:45),
  which `Alarm.Schedule.Relative` cannot express (minute granularity). Every
  chain member is scheduled as `.fixed(Date)` for the next occurrence only, and
  the engine reschedules on launch, foreground, and dismissal. Consequence to
  verify in milestone 1: a dismissal from the system UI must reach
  `DismissAlarmIntent` so the next occurrence gets scheduled without opening
  the app.
- **Stop is "I'm up".** There is no snooze, so the system alarm's stop button
  carries the dismiss intent: any stop cancels the entire chain and (for
  repeating alarms) schedules tomorrow's.
- **Backup chain budget.** iOS caps pending notifications at 64, so the backup
  covers phase 1 + A–E + three plateau checkpoints (9 per occurrence), not every
  E-repeat.
- **Persistence is JSON** (`Application Support/fathom.json`), settling §7's
  open decision. Scheduled-chain state lives in `UserDefaults` so dismissal can
  cancel siblings across launches.

## Milestone status (§8)

1. **Walking skeleton — code complete, unverified.** The chain scheduler,
   dismiss intent, and backup chain are written but every row of the §9
   reliability matrix still needs a real iPhone. AlarmKit specifics the design
   flags as spec-to-verify (28 fixed alarms per occurrence, exact-30 s custom
   sounds, restart persistence, stop-intent delivery) are exactly that.
2. **Scene port — code complete.** §5 constants verbatim; compare side-by-side
   against the prototype at all three depths before calling it done.
3. **Three screens — code complete** with placeholder audio and JSON persistence.
4. **First real pair** — not started; compose *Dawn* in Logic per §6.
5. **Daily-driver build** — blocked on 1–4.
