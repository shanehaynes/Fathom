# Design: a two-phase alarm clock for iOS

*Founding design document. The interactive visual reference lives at [`prototype/design-prototype.html`](prototype/design-prototype.html) — open it in a browser; everything in §5 is extracted from it and the Swift build must match it.*

---

## 1. Vision and principles

An iOS alarm clock that reproduces the two things the Loftie hardware clock gets right — a two-stage wake (gentle, then firm) and sounds that are genuinely pleasant to wake to — wrapped in a visual identity of its own: a prismatic sheen of light under a dark ocean.

The principles below are the tiebreakers for every future decision. When a feature idea or design question comes up, it must survive all of them.

1. **The gap replaces snooze.** The grace period between phase 1 and phase 2 is chosen the night before, with intention — never negotiated half-asleep. There is no snooze button anywhere in the app.
2. **Light is ambient, never figurative.** The background is a property of the water, not a creature or object to watch. (A line-based "eels of light" variant was prototyped and rejected; formless orbs won. Do not reintroduce figurative light.)
3. **The interface speaks only warm white.** Every selected or active control is warm white `#f2e8d5`. The water owns all other color. No accent palette, ever.
4. **No daytime destination.** Nothing in the app rewards opening it during the day. No feeds, no stats, no streaks, no content after "I'm up."
5. **Local-first, forever.** No accounts, no backend, no subscriptions, no analytics. A missed alarm is the only failure that matters, and a server dependency is a new way to fail.
6. **Settings sprawl is the enemy.** Every control must earn its place. The full settings surface is: alarm time, sound pair, day dots, gap length, bedside-mode toggle, sunrise lamp (v2).

## 2. Name

Candidates, all drawn from the underwater-light identity:

| Name | Rationale |
|---|---|
| **Fathom** (recommended) | A measure of depth, and "to fathom" — to come to understand. Waking as surfacing into comprehension. Short, wordmark-friendly. |
| **Sounding** | Double meaning: taking a depth sounding, and sound itself. The most conceptually exact, slightly softer as a product name. |
| **Undertow** | Evocative, but pulls the wrong direction — the app carries you *up*. |
| **Beneath** | The place the light lives. Atmospheric but generic as a store listing. |

**Recommendation: build under the name Fathom.** Both "Fathom" and "Sounding" are common words — check App Store collisions before shipping publicly; the name can change up to the TestFlight moment at near-zero cost. The repo stays `alarm-clock` until then.

## 3. The two-phase mechanic (behavioral spec)

### Timeline

For an alarm set at time `T` with gap `G ∈ {3, 6, 9}` minutes:

```
T          Phase 1 — gentle sound, 30 s, fade baked into the file. Then silence.
T + G      Phase 2 — begins and escalates:
  +0:00      file A (warm, present — already clearly audible)
  +0:30      file B (brighter, fuller)
  +1:00      file C (rhythmic, insistent)
  +1:30      file D (near-full energy)
  +2:00      file E (plateau) — repeats every 30 s until dismissed, cap 15 min
```

Phase 2 is contiguous — each 30 s file starts as the previous ends, no silence between steps — and the climb is linear: A opens clearly audible, each step adds an even increment, the plateau never gets louder — insistent, never punishing. (Device testing killed the original smoothstep-with-gaps: the gaps read as the alarm giving up, and a quiet A is indistinguishable from phase 1.)

### State machine

```
scheduled ──T──▶ phase1_playing ──30s──▶ gap_waiting ──T+G──▶ phase2_escalating ──2min──▶ phase2_plateau
     │                 │                     │                      │                          │
     │              "I'm up"              "I'm up"               "I'm up"                   "I'm up"
     │                 ▼                     ▼                      ▼                          ▼
     └──(edit/off)──▶ idle ◀────────────── done ◀──────────────── done ◀──────────────────── done
```

- **Dismissing at any point cancels everything downstream.** "I'm up" during phase 1 or the gap means phase 2 never fires — this is the core improvement over the Loftie, which plays both phases unconditionally.
- Phase 2 has **no snooze** (principle 1). The only affordance is "I'm up."
- After "I'm up": nothing. The alarm returns to idle/scheduled-for-tomorrow. No summary, no content.

### Scheduling semantics

- **Day dots (M T W T F S S):** an alarm fires on its enabled days. A day with no dots enabled = one-shot alarm for the next occurrence of `T`, then disarms.
- **Editing an armed alarm** cancels and reschedules its entire chain atomically.
- **Multiple alarms** are allowed (e.g. weekday 6:10, weekend 8:00). Overlapping chains: if a phase-2 chain is active when another alarm's phase 1 would fire, the active chain wins and the new phase 1 is suppressed (log-and-verify in milestone 1; genuinely rare).

### Edge cases and redundancy

| Case | Required behavior |
|---|---|
| Silent switch / Focus / DND | Alarm fires audibly regardless — AlarmKit system alarms break through. Verify on-device in milestone 1. |
| Phone restarted overnight | AlarmKit alarms persist across restart (verify milestone 1). If they don't: rescheduling on next app launch is not sufficient for a restart at 3am — this becomes a known limitation to document, mitigated by the backup chain if notifications survive restart. |
| App force-quit | System alarms fire independently of app process (verify milestone 1). In-app continuous audio after tap simply starts on the tap. |
| Low battery / Low Power Mode | Chain must still fire (verify). Bedside always-on mode requires charging (§4), so this mainly affects launchpad mode. |
| Backup chain | Until AlarmKit reliability is proven across all rows above, schedule a parallel `UNUserNotificationCenter` chain (time-sensitive local notifications with 30 s custom sounds) offset +30 s from each AlarmKit fire, cancelled whenever the real alarm is acknowledged. Remove only if milestone-1 testing proves it redundant. |

## 4. Screens

Three screens. There is no fourth.

### Tonight (home)

The resting state. Near-black, spectrum asleep at night depth, large thin clock numerals, next-wake line (`wake at 6:10 · Dawn`), and one action: **Wind down** (starts the sleep sound with a fade-out timer; the practical hook that gets the phone plugged in and face-up).

Two modes:

- **Launchpad (default):** open, wind down, screen locks normally.
- **Bedside ("stay on while charging"):** opt-in toggle. Screen stays on displaying Tonight while charging only. Requirements: `isIdleTimerDisabled` only while plugged in and on this screen; OLED mitigations — sub-1 fps scene updates at night depth, slow pixel-drift of the entire composition (±8 px over minutes), auto-dim below system brightness; optional **red-shift/blackout** sub-mode that clamps the scene to deep red at minimal luminance.

### Alarm (settings)

The daytime screen — the one place the spectrum is fully visible, a few feet down (§5, day depth). Controls, top to bottom:

- Time (large numerals, wheel picker on tap)
- **Sound pairs** — cards named by pair (Dawn, Fountain, …). Tap to preview: 5 s of gentle → crossfade → 5 s of firm. Selection = warm-white border.
- **Day dots** — M T W T F S S, tap to toggle
- **Gap** — 3 / 6 / 9 pills
- **Sunrise lamp** — toggle, flagged v2 (§8)

Controls float on translucent ink cards (`rgba(6,9,14,0.5–0.55)`) so they hold against the bright scene — brightness confirmed correct in the prototype.

### Wake (phase 2)

Appears when the user engages the firing alarm and the app foregrounds. Scene at current wake depth (rising), clock, pair name + phase label (`gentle` / `rising` / `full`), and a single warm-white button: **I'm up**. Dismissal ends everything (§3). Nothing follows.

## 5. Visual system

### The scene

The screen is the water's surface viewed from directly above; the viewer looks straight down. Depth is a fictitious z toward the viewer.

**Geometry rule (invariant):** motion on the x/y plane is constant, slow, and undirected — where a bloom sits at any moment is chance. The depth parameter moves only z — brightness, saturation, apparent size — and changes **only when the time-of-day state changes**. Depth must never translate bloom positions.

Six radial blooms on a near-black ground, additively blended, hues drifting independently around the full wheel. Constants (extracted from `prototype/design-prototype.html`; the SwiftUI port must match):

| Constant | Value |
|---|---|
| Ground | `#06090e` |
| Bloom count | 6 |
| Base position i = 0…5 | `cx = 0.12 + 0.76·((0.37i + seed) mod 1)`, `cy = 0.18 + 0.68·((0.53i + 0.7·seed) mod 1)` |
| Base radius (× width) | `0.30 + 0.28·((0.71i) mod 1)` |
| Drift | `x += 0.10·sin(0.00013·spx·t + φ)`, `y += 0.07·cos(0.00011·spy·t + 1.3φ)` where `spx = 0.6 + ((0.29i) mod 1)`, `spy = 0.4 + ((0.41i) mod 1)`, `φ = 1.7i + 6·seed`, t in ms |
| Base hue | `(60i + 360·seed) mod 360`, drifting at `0.0018 + 0.0016·((0.43i) mod 1)` deg/ms |
| Depth I → saturation | `40 + 45·I` (%) |
| Depth I → lightness | `30 + 28·I` (%) |
| Depth I → alpha | `0.07 + 0.34·I` (radial: core → transparent edge) |
| Depth I → radius scale | `0.85 + 0.55·I` |
| Blend | additive (`lighter` / `.plusLighter`) |
| Veil | radial `130%×110%` at `(50%, 42%)`, `rgba(6,9,14, 0.28 → 0.74)`; on Wake, veil opacity `1 − 0.45·I` |

### Depth per state

| State | Depth I |
|---|---|
| Night (Tonight) | `0.10` |
| Wake (phase 1, gap) | `0.35` — a visible lift above night, not yet day |
| Wake (phase 2) | `0.85 + 0.15·smoothstep(min(m/2, 1))` after a 3 s ease up from 0.35; m = minutes since phase 2 began. Opens at day depth — the firm phase is a few feet down — and holds at 1.0 |
| Day (Alarm) | `0.85` |

State transitions (night→wake handled by the ramp itself; wake→idle, entering Alarm) ease over a few seconds rather than stepping.

### Palette and type

| Token | Value | Use |
|---|---|---|
| `warm` | `#f2e8d5` | Every selected/active control; the only UI color |
| `ink` | `#06090e` | Ground |
| `ink2` | `#0a0f16` | Cards/surfaces |
| `textHi` | `#d8e2ec` | Numerals, primary text |
| `textMid` | `#7e8ea0` | Secondary |
| `textLow` | `#4a5768` | Labels, tags |
| `line` | `rgba(140,170,200,0.14)` | Hairlines |

Type is the system face (SF): clock numerals thin (weight ~200) with monospaced digits; labels small, uppercase, letterspaced. Single committed dark theme — the app is only ever seen in a dark room or against its own water.

## 6. Sound design brief (self-composed)

The sounds are the product; the app is the frame. v1 target: **two or three pairs done well**, not a library.

### Pairs

A wake sound is a **pair** — one identity with a gentle half and a firm half sharing musical DNA: same key, same timbre family, escalating energy. Working names: *Dawn* (warm strings → chimes), *Fountain* (water → bright bells). Picking a pair picks both halves; they are never mixed and matched.

### Phase 1 file (×1 per pair)

- 30 s exactly, **fade-in ≥ 3 s and full fade-out baked into the file** (the file is the envelope — no runtime fading needed at the alarm layer)
- Warm low-mid spectral content (roughly 150 Hz – 2 kHz energy), slow attacks, no transients, no percussion
- Quiet target: noticeably below the phase-2 chain (≈ −6 dB relative)

### Phase 2 chain (×5 per pair: A–E)

Each 30 s. Fired back-to-back at +0:00 / +0:30 / +1:00 / +1:30 / +2:00 into phase 2 (§3); each file should end where the next begins (short fades only, no silence).

- **A** introduces the pair's melodic identity at conversational energy
- **B–D** add layers: brightness (upper octaves, 2–8 kHz), rhythmic density, fuller voicing — hotter in energy more than in raw loudness
- **E (plateau)** must **loop seamlessly** (compose to bar boundaries, no reverb tail crossing the loop point) and sustain indefinitely without grating: constant energy, evolving texture — change the voicing, never the intensity
- In-app continuous versions: once the app is foregrounded, longer loop-based renditions of the same material take over for gapless playback

### Production

- Compose in GarageBand/Logic on the Mac. Practical workflow: build the full plateau arrangement first, then create A–D by *removing* layers — guarantees shared DNA and consistent mixing.
- Export: bundle sounds as `.caf` (48 kHz, 16-bit); in-app versions as AAC `.m4a`. Loudness-match all files per pair (target ≈ −16 LUFS for the chain, −22 LUFS for phase 1); the escalation should come from arrangement, not mastering tricks.
- Preview asset per pair: the 5 s + 5 s crossfade clip used by the Alarm screen.

## 7. Technical architecture

- **Platform:** SwiftUI, iOS 26+, iPhone only. Xcode on the Mac; day-to-day editing can happen anywhere, building/signing happens on macOS.
- **Alarms:** AlarmKit. Each armed alarm expands to its chain of system alarms (phase 1 + A–E + E-repeats). Custom 30 s sounds from the app bundle. All chain members carry metadata linking them to the parent alarm so any dismissal cancels siblings. *AlarmKit specifics (sound looping, restart persistence, custom stop-button labels, repeat limits) are spec-to-verify in milestone 1 — trust the device, not the docs.*
- **Wake handoff:** engaging the system alarm foregrounds the app → Wake screen; `AVAudioSession` (`.playback`) takes over with the continuous rendition at the correct ramp position (computed from wall-clock time since phase-2 start).
- **Scene:** SwiftUI `Canvas` inside `TimelineView` (`.animation` while visible; `.periodic(1 s)` or slower in bedside night mode). The math is §5's table verbatim. Metal only if Canvas can't hold frame rate — it should, at 6 gradients.
- **Persistence:** alarms and settings in a single local store (SwiftData or a JSON file — decide in milestone 3; the model is tiny). No network entitlements at all.
- **Out of scope forever:** accounts, backend, subscriptions, sleep tracking, social anything, Android/web (a dedicated-tablet web build may be revisited as a separate project).

## 8. Scope and roadmap

**v1:** everything in §3–§7 with 2 sound pairs. **v1.x:** HomeKit sunrise (fade a smart bulb up 10–15 min before `T`), blackout/red-shift polish, third+ pairs, Apple Watch surface if AlarmKit gives it for free. **Never:** anything on the out-of-scope list.

Milestones, each independently verifiable:

1. **Walking skeleton (the go/no-go):** bare app, one hardcoded alarm, chained AlarmKit alarms with custom sounds. Proves the §3 edge-case table on a real iPhone. *If AlarmKit fails a must-have row, the fallback architecture (notification-chain + bedside-mode-primary) gets designed before any UI work.*
2. **Scene port:** §5 in SwiftUI Canvas, side-by-side against the prototype at all three depths.
3. **Three screens:** full UI + persistence, placeholder audio.
4. **First real pair:** compose *Dawn* per §6; live with it.
5. **Daily-driver build:** personal TestFlight install, reliability matrix green two weeks running, second pair, then decide whether the App Store is even interesting.

## 9. Reliability test matrix

Run before trusting it as the only alarm (milestone 1, again at milestone 5, and after every iOS major update). Every row must wake the room:

| # | Condition | Pass criteria |
|---|---|---|
| 1 | Silent switch on | Both phases audible at full scheduled volume |
| 2 | Sleep Focus + DND | Both phases fire with full-screen presentation |
| 3 | App force-quit before bed | Chain fires; tap opens app into Wake |
| 4 | Phone restarted, not unlocked overnight | Chain fires (or documented limitation + mitigation) |
| 5 | Low Power Mode, < 20 % battery | Chain fires |
| 6 | OS update pending overnight | Chain fires |
| 7 | Alarm edited after arming | Old chain fully cancelled — no ghost fires |
| 8 | "I'm up" during phase 1 | Phase 2 provably never fires |
| 9 | Two alarms overlapping | Active chain wins; no double audio |
| 10 | Bedside mode, 8 h charging | Screen on all night, correct depth, battery at 100 %, no scene freeze |
