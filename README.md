# Hind Squadron Tracker (DCS + MOOSE)

Persistent‑style squadron tracking for a Mi‑24P flight in DCS World, with simple campaign state and slot enforcement. This script is designed to run inside a mission that uses the MOOSE framework.

## What This Script Does

- Tracks 4 airframes and 6 pilots in a single shared state table.
- Manages supply points (abstract ammo/fuel).
- Tracks airframe damage states: `OK`, `Minor`, `Major`, `Destroyed`.
- Tracks pilot fatigue states: `Fresh`, `Tired`, `Exhausted`.
- Enforces slot availability by group name.
- Provides an F10 menu for status and basic testing.

## Key Concept: Airframe Alignment

Each Hind airframe is mapped to a DCS group name. The script enforces that mapping:

- `HIND-01`
- `HIND-02`
- `HIND-03`
- `HIND-04`

When a player spawns into a group whose name matches one of these airframes, the script checks its damage state. If the airframe is `Major` or `Destroyed`, the group is destroyed immediately and a message is displayed.

## Requirements

- DCS World mission using MOOSE.
- `Moose.lua` must be loaded **before** `hind_squadron_tracker.lua`.

## Mission Editor Setup

1. Place 4 Mi‑24P groups.
2. Set **Skill** to `Client` for each group.
3. Name the **GROUPS** exactly:
   - `HIND-01`
   - `HIND-02`
   - `HIND-03`
   - `HIND-04`

## Trigger Setup (Recommended)

Create two mission start triggers:

1. `MISSION START` → `DO SCRIPT FILE` → `Moose.lua`
2. `MISSION START` → `DO SCRIPT FILE` → `hind_squadron_tracker.lua`

## Script Overview

### State Structure

The state is held in `HIND_SQUADRON.State`:

- `Turn`: campaign turn counter.
- `SupplyPoints`: shared resource pool.
- `Airframes`: list of airframes with `Id`, `Damage`, `Notes`.
- `Pilots`: list of pilots with `Id`, `Name`, `Fatigue`, `Notes`.

### Airframes

- `SetAirframeDamage(id, damage)` validates and sets a damage state.
- `IsAirframeFlyable(id)` returns `false` if `Major` or `Destroyed`.

### Pilots

- `SetPilotFatigue(id, fatigue)` validates and sets fatigue state.
- `ApplySortieFatigue(pilotId)` advances `Fresh → Tired → Exhausted`.
- `RecoverPilotFatigueAll()` moves fatigue back one step for all pilots.

### Supply

- `AddSupply(points)` adds supply (clamped to 0..999).
- `SpendSupply(points)` subtracts supply if enough is available.

### Turn Advancement

`AdvanceTurn()`:

- Increments turn.
- Recovers pilot fatigue by one step.
- Adds +2 supply points.
- Announces the change.

### UI / Reporting

- `BuildStatusText()` produces a multi‑line status report.
- `Announce(text, seconds)` sends a MOOSE `MESSAGE` if available, else a DCS `outText`.

### Enforcement (Slot Blocking)

On `S_EVENT_BIRTH`:

- If the spawning group name matches a tracked airframe and its damage is `Major` or `Destroyed`,
  the group is destroyed and a message is shown.

### F10 Menu

The menu is created under **F10 → Other → Hind Squadron (Campaign)**:

- Show Squadron Status
- Advance Turn (Between Sorties)
- Test helpers: spend supply, apply fatigue, set damage states

## Debug Note

This script currently shows a one‑time message at mission start:

```
HIND script loaded
```

This is a load confirmation and can be removed once your mission is stable.

## Common Issues

- **No F10 menu**: MOOSE wasn’t loaded first, or the script didn’t run.
- **No “HIND script loaded” message**: the script file is not being executed.
- **Slots not blocked**: group names don’t match `HIND-01`..`HIND-04`.

## File

- `hind_squadron_tracker.lua`

