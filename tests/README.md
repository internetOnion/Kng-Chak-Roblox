# Tests

Tests for the shared game code run outside Studio, in [Lune](https://github.com/lune-org/lune) (installed by Rokit). CI runs them on every PR.

```bash
lune run test          # every spec
lune run test Planet   # only spec files whose path contains "Planet"
./scripts/check.sh     # format, lint, types and tests, the same as CI
```

## Writing a test

- Put it in `tests/`, mirroring `src/shared`, named `<Module>.spec.luau`.
- Require game code with `@shared/...` and the test kit with `@testkit`, which gives `describe`, `it` and `expect` (`toBe`, `toEqual`, `toBeCloseTo`, `toThrow`).
- Test what a module does from the outside, through its public methods and events, never its private fields. Once the Run exists, most tests drive a Run with scripted input and check the events and snapshot it produces.

## What shared code can use

Shared game code (`src/shared`) has to load both in Roblox and in Lune, so:

- **Requires** are path strings: `require("../Util/Signal")`, never `require(script.Parent...)`. Both Roblox and Lune resolve them the same way.
- **Roblox globals available in tests:** `task`, `Vector2`, `Vector3`, `Color3` (including `fromHex`), `CFrame` and `Enum`. The runner installs them from Lune's roblox library.
- **Not available:** `game`, `workspace`, `Instance`-based APIs and `Random`. Code that needs them belongs in a view or adapter, not in the simulation. Randomness comes from a seeded RNG passed into the Run.

## Replays

`tests/Replays/*.luau` are recorded runs: a seed, each frame's input and the event log the run produced. `tests/Run/Replay.spec.luau` replays them and expects exactly the same events and ending.

- `Bot.luau` is recorded by `lune run record-replay` (a small bot flies at rocks). Re-record it after a change that's meant to change how runs play out.
- To capture a real playtest, press **F7** in a Studio playtest: the run's recording is printed to Output as a Luau module. Save it under `tests/Replays/` to replay a bug exactly.
