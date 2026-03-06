# Hind Squadron Tracker (DCS + MOOSE)

Persistent‑style squadron tracking for a Mi‑24P flight in DCS World, with simple campaign state and slot enforcement. This script is designed to run inside a mission that uses the MOOSE framework.

## What This Script Does

- Tracks 4 airframes and 6 pilots in a single shared state table.
- Manages supply points (abstract ammo/fuel).
- Tracks airframe damage states: `OK`, `Minor`, `Major`, `Destroyed`.
- Tracks pilot fatigue states: `Fresh`, `Tired`, `Exhausted`.
- Tracks pilot status: `Alive`, `Dead`.
- Enforces slot availability by group name.
- Provides an F10 menu for status and basic testing.
- Supports an optional external pilot roster file to override pilot names.

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
- To persist state between runs, DCS must allow `io` and `lfs` (edit `MissionScripting.lua`).

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
- In-mission events:
  - On `S_EVENT_HIT`/`S_EVENT_DAMAGE`, damage is set to `Minor` or `Major` based on remaining life.
  - On `S_EVENT_DEAD`/`S_EVENT_CRASH`/`S_EVENT_COLLISION`/`S_EVENT_PILOT_DEAD`, damage is set to `Destroyed`.

### Pilots

- `SetPilotFatigue(id, fatigue)` validates and sets fatigue state.
- `ApplySortieFatigue(pilotId)` advances `Fresh → Tired → Exhausted`.
- `RecoverPilotFatigueAll()` moves fatigue back one step for all pilots.
- In-mission events:
  - On `S_EVENT_LAND`, the landing player's fatigue is advanced if their player name matches a pilot `Name` or `Id`.

### Pilot Roster Override (Optional)

If the file below exists, pilot names are overridden at mission start:

- `Saved Games\DCS\HindSquadronPilots.lua`

This file must return a Lua table in one of these formats:

```lua
-- Array of names (maps to PILOT-01..PILOT-06 by index)
return { "Viper", "Bear", "Saber", "Cobalt", "Rook", "Mako" }
```

```lua
-- Array of objects
return {
  { Id = "PILOT-01", Name = "Viper" },
  { Id = "PILOT-02", Name = "Bear" },
}
```

```lua
-- Map of Id -> Name
return {
  ["PILOT-01"] = "Viper",
  ["PILOT-02"] = "Bear",
}
```

Notes:

- If the roster file is present, names are applied to the current state and saved.
- This requires `io` and `lfs` to be desanitized (same as persistence).

### Supply

- `AddSupply(points)` adds supply (clamped to 0..999).
- `SpendSupply(points)` subtracts supply if enough is available.
- Repairs consume supply on `AdvanceTurn()`:
  - `Minor` costs 1, `Major` costs 2, `Destroyed` cannot be repaired.

### Turn Advancement

`AdvanceTurn()`:

- Increments turn.
- Recovers pilot fatigue by one step.
- Repairs damaged airframes if enough supply is available.
- Adds +2 supply points.
- Announces the change.

### Persistence

If a saved state file is present, it is loaded at mission start. If not, the default state is used.
Changes are saved automatically when state-mutating functions are called.
On successful load, an on-screen message shows the file path used.

Default save location:

- `Saved Games\DCS\HindSquadronState.lua` (when `lfs` is available)

Optional customization:

- You can change the save location/filename by editing `HIND_SQUADRON.StateFilePath` and `HIND_SQUADRON.StateFileName` in `hind_squadron_tracker.lua`.

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
- Test helpers: spend supply, apply fatigue, set damage states, revive `PILOT-01`

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
- **State not saving/loading**: `io` and `lfs` are still sanitized in `MissionScripting.lua` or the state file path is invalid.

## File

- `hind_squadron_tracker.lua`

