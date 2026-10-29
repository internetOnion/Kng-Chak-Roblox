# Kng Chak art guide (Roblox: Toy Box)

Decided 2026-10-29. This is the look of the **Roblox version only**; the Unity version keeps its own flat vector + glow guide. Reference for building models and the arena in Roblox Studio. Numbers are starting values; change this file when they change.

The look was picked from three prototype style tiles. Screenshots and code are on the throwaway branch `prototype/art-style` (folder `prototypes/art-style/`).

## Style: Toy Box
- **Chunky 3D toys.** Every object is built from soft, rounded shapes: balls, capsules, cylinders, rounded blocks and wedges. Proportions are a little oversized and friendly, like plastic toys on a table.
- **Bright and saturated.** A bright violet space sky, a turquoise and green planet, a red fire-brigade rocket. No muddy greys except where a material is meant to look heavy (iron).
- **Bold black outlines** on the planet, the ship and every rock, so shapes read at phone size against the sky.
- **Glow still means "this matters".** Only energy uses the Neon material: the flame, the orbit band, the comet tail, primed rocks, stars, PERFECT and combo callouts. Rocks, the hull and the planet never glow on their own.
- **Shape before colour.** Every rock type must be recognisable by silhouette alone (colour-blind safe) at phone size.
- **Light from above and slightly behind the camera,** with real shadows on, so the toys feel solid.
- Fonts: the brand fonts, Atomic Age (display) and Jost (UI and numbers), aren't among Roblox's font families (checked in Studio on 2026-10-29 for #12), so built-ins stand in: **Fredoka One** for display, which fits the toy look, and **Montserrat** (Medium and Bold) for UI and numbers, the closest geometric sans to Jost. Revisit before the M4 menus if Roblox adds a way to use them.

## Shape language
| Object | Built from | Must read as |
|---|---|---|
| Planet (Ember) | Turquoise ball, green land bumps on the surface, white ice cap at the north | A friendly toy globe |
| Lancer, soft | Red body tube, yellow reflective stripe, white fins, dark engine grille, light-blue window, round cream helmet nose | A cute fire-brigade rocket |
| Lancer, hard (boosting) | Same body; the helmet swaps for a white spear with a red tip | The spear is out: it breaks rocks |
| Flame | Three nested Neon bands behind the engine, longer when boosting | The push zone; its size matches the zone |
| Rock | Lumpy brown ball with darker crater dots | Plain rock |
| Shard | Small angular wedge | Small and sharp |
| Comet | Icy white ball with a Neon cyan bubble tail pointing away from the planet | Fast; push it first |
| Iron | Blue-grey cube turned at an angle, with dark rivets | Heavy metal |
| Cluster | Four purple bubbles stuck together | Splits apart |
| Gold | Shiny yellow ball with a white highlight and sparkles | Prize |
| Primed (any rock) | Pink fill and pink outline instead of black | Pushed and ready to break |
| Orbit band | Ring of Neon cyan dashes | Safe orbit |

## Palette
| Use | Colour |
|---|---|
| Space sky | `#3d3ad8`, stars white and `#ffe066` |
| Planet ocean, land, darker land, ice | `#2fc4ff`, `#5ee05e`, `#3fb34a`, `#ffffff` |
| Orbit band | `#6ff3ff` (Neon) |
| Lancer body, stripe, fins, grille, window | `#ff3b3b`, `#ffd400`, `#ffffff`, `#3a3a4a`, `#8fe3ff` |
| Helmet nose, spear nose | `#fff1b8`, `#f4f6ff` (red tip `#ff3b3b`) |
| Rock, crater | `#c98b55`, `#8f5c34` |
| Shard | `#e8b27a` |
| Comet, tail | `#c9f7ff`, `#7fe6ff` (Neon) |
| Iron, rivets | `#7487a3`, `#3c4658` |
| Cluster | `#b25fd0` |
| Gold | `#ffcf2e` |
| Primed | `#ff4fd8` |
| Heat: soft (red-orange) | edge `#ff4a1c`, mid `#ff9a1f`, core `#ffe066` |
| Heat: boost (white-gold) | edge `#ffa030`, mid `#ffe08a`, core `#ffffff` |
| Heat: slingshot (blue) | edge `#2f7dff`, mid `#7fe6ff`, core `#f2ffff` |
| Heat: stunned (grey) | edge `#40444d`, mid `#6a707c`, core `#9aa0aa` |

The rock colours here replace the old palette, and the rock type data should follow them.

## Tint, don't rebuild
Anything whose colour changes in play is one model whose part colours are set from data: the heat bands, the primed state, the planet's land and ocean per district, the shield ring. Never make a second model just for a colour.

## How models are made
- **Studio parts first:** Ball, Cylinder, Block and Wedge parts in SmoothPlastic, and a sphere mesh on a block for stretched shapes (capsules, ellipsoids). Most of the game, including the ship, rocks and planet, can be built this way.
- **Meshes only when parts can't do it** (the Inferno boss, a detailed ship skin). Make them in Blender, keep them low-poly with flat colours, and upload them as MeshParts. Every upload goes through Roblox moderation, so upload ahead of need.
- Each model lives in the assets folder and is looked up by name, so swapping greybox for final art changes only assets, never code.
- **How the views read a model:** build it around the origin with its front along −Z; the view resets the model's pivot to the origin before placing it. Rocks are built at radius 1 (the view scales them to their type's radius) and live at `Assets/Rocks/<type id>` (`Rock`, `Comet`, `Iron`, `Cluster`, `Shard`, `Gold`); parts named `Body…` are painted with the type's tint. The planet is built at radius 10. Each model carries a `Highlight` named `Outline` (black; the rock view turns it pink while primed). The ship's `Spear`, `SpearTip` and `Flame` parts are driven by the ship view.
- **Names:** `kc_<group>_<name>_<variant>`, e.g. `kc_rock_iron_a`, `kc_ship_nose_hard`, `kc_planet_ember`.
- Keep part counts low: a rock about 5–10 parts, the ship about 15, the planet about 15. Up to 7 rocks are in flight at once on a phone.

## Outlines
- Black outlines come from a Highlight on each model (outline only, no fill, depth mode Occluded). The primed state swaps it to a pink outline with a pink fill.
- **Budget:** Roblox shows at most 31 Highlights at once. Planet, ship, up to 7 rocks, shards, and the boss's plates fit, but count them. If a scene goes over, use the fallback: a black copy of the shape, slightly larger and drawn behind it.

## Scale, camera and lighting
- 1 stud = 1 arena unit. Planet radius 10, orbit band up to 4.5 above the surface (radius 14.5), arena edge at radius 66. A rock's size in the data is its **radius** (a size 1.4 rock is 2.8 studs across). The ship is about 3.2 studs long.
- Objects sit at real heights above the play plane instead of sorting layers: sky at −16, planet centred on the plane, rocks at +2, ship at +3, VFX above them, world UI on top.
- **Camera:** high above the plane with a fairly narrow field of view (**30°**), tilted 18° from straight down, top of the screen toward the north. The style tile (#17) moved it from 20° to 30°: at 20° the camera sat about 284 studs up, and at low graphics quality Roblox stopped drawing anything past about 300 studs, which blanked the top of the screen. At 30° everything on screen is within about 225 studs. **Zoom: CamView 50**, chosen over ~35 in the M1 phone playtest (#18); final models are sized for it.
- **Lighting:** bright daytime, shadows on, colour correction with saturation about +0.25 and contrast about +0.12, and mild bloom so Neon glows without washing out. The values settled in the style tile (set by `Views/Stage`, which also switches off a template's atmosphere haze, depth of field and sun rays):
  - Lighting: ClockTime 13.5, GeographicLatitude 20, Brightness 2.6, Ambient `#8c86c8`, OutdoorAmbient `#b8b2ff`, GlobalShadows on.
  - Bloom: Intensity 0.35, Size 18, Threshold 1.4. Colour correction: Saturation 0.25, Contrast 0.12, Brightness 0.04.
- **Sky:** a flat `#3d3ad8` backdrop 16 studs below the plane, with Neon stars 0.4–1.1 studs across (80% white, 20% `#ffe066`), about 4 per 1,000 square studs.
- **Settled shapes (from the style tile):** the orbit band is 36 Neon beads (0.45 × 0.3 × 1.4 studs, 25% transparent) rather than a solid line; the flame is three nested Neon ellipsoids (edge, mid, core at 100%, 72% and 44% of the length) coloured from the heat ladder; the Lancer's soft nose is a 1.3-stud helmet ball, swapped for a long white spear with a red tip while boosting.

## Who makes what
| Source | Assets |
|---|---|
| Studio parts | Ship parts, rocks, planet, orbit band, sky and stars, greybox |
| Blender meshes | Inferno boss, detailed cosmetic skins |
| Particles, beams and Neon in Studio | Flame, sparks, impacts, trails, edge ripple, shield ring |
| Code | Fuel arc, threat ring, chevron, radar |
| Packs (CC0 or bought) | Sound effects and music only |
| AI | Moodboards and concept references only, never shipped art |

## UI
Chunky, rounded and bright to match: thick rounded buttons, bold outlined numbers, the same palette. Readable on a phone first.

## Asset checklist in production order
**Phase 0: greybox.** Toy-style placeholder models for each rock type, the ship and the flame; arena data; phone zoom check.

**Phase 1: style tile.** Finish the Toy Box tile in Studio from the prototype: Ember planet, the Lancer soft and hard, all rock types, the flame. Check it on a phone.

**Phase 2: Ember gameplay**
- [ ] Lancer: helmet nose (soft), spear nose (hard), body, stripe, engine grille, fins, window
- [ ] Rocks: shard, rock, comet (+ tail), iron, cluster, gold, 2–3 shape variants each, the primed state, 3–4 debris chunks
- [ ] Ember planet: ocean, land, ice cap, atmosphere rim
- [ ] Sky: violet backdrop, 2 star layers
- [ ] VFX: flame, sparks, impact burst, ignition ring, shield ring, PERFECT flash
- [ ] World UI: fuel arc, threat ring, chevron, edge ripple (code)

**Phase 3: UI.** Fonts, HUD (HP %, combo, score), radar, upgrade card frame and Flame/Spear/Orbit icons, pause and results screens.

**Phase 4: later.** Inferno boss (plates, core, burn VFX), Glacier and Foundry planets (their own land and ocean colours and sky tint), cosmetic part skins.
