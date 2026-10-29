# PROTOTYPE: art style (throwaway, never merge)

**Question:** what should a brighter, cartoonish, Roblox-feeling Kng Chak look like, instead of the flat-vector-plus-glow direction in the art guide?

Three style tiles of the same scene, all at real game scale: Ember planet, orbit band, the Lancer cruising (soft nose) and boosting (spear), each rock type and one primed rock.

| Variant | Look | Camera |
|---|---|---|
| A · Toy Box | Smooth chunky toy shapes, bold black outlines, bright violet sky, saturated colour | Slight tilt (18°) |
| B · Brick Classic | Everything built from studded blocks: classic Roblox | Stronger tilt (32°) |
| C · Neon Arcade | Dark sky, candy-neon glow, rocks outlined in their type colour | Straight down |

## Run it

On this branch, with `rojo serve` connected, press Play in Studio. The bar at the bottom (or ← / →) switches variants. From the command bar: `workspace:SetAttribute("StyleVariant", "B")`.

The code is `src/client/Dev/StylePrototype.luau`, switched on in the client's `DEV_TOOLS`.

## Verdict (2026-10-29)

**A · Toy Box won.** It reads best at phone size: every rock type has its own silhouette, the primed rock pops, and it feels bright and fun. B felt the most "Roblox" but its blocky rocks are harder to tell apart, and its strong tilt shows the planet's side. C depends on neon glow, which looks flat at low graphics quality on cheap phones.

Consequence: the art is 3D toy models built in Studio, not 2D images on flat parts. The art guide, spec #1 and the art tickets were updated to match.
