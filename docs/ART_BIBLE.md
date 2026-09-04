# ART BIBLE — Injection Tycoon MVP
**Status:** LOCKED for PROTOTYPE  
**Style:** Clean cartoon isometric  
**Platform:** Mobile portrait 720×1280 (Godot stretch `canvas_items` / `expand`)  
**Engine:** Godot 4.x, renderer `mobile`

Gameplay readability > polish. Line / mold / defect / heat must be readable at arm's length on a 5" phone.

---

## 1. Art Style

| Field | Value |
|---|---|
| Art Style | Clean cartoon isometric. Soft fills, 2–3px dark outlines, no realistic metal/grime. |
| Camera | Orthographic isometric, **2:1** (classic 26.565°). No perspective foreshortening. |
| Perspective | Factory floor reads as a diamond. Machine sits center. Hopper left-back. Bin right-front. |
| Character Proportion | N/A (MVP has no staff). Future operators: chibi 1.5 heads, silhouette-first. |
| Enemy Proportion | N/A |
| Color Palette | See §3. Cool factory blues + warm amber/red status. Never gray-on-gray. |
| Lighting | Flat key from **top-left**. One highlight plane + one shadow plane per volume. No baked AO. |
| Shadow | Soft contact blob under machine/bin only. Alpha 25%, #1A2229. No long cast shadows. |
| Outline | 2px (#1A2229) on factory objects. 1.5px on HUD icons. No sketchy/variable width. |
| Texture Detail | Solid fills + 1 stripe/rivet max. No noise textures in MVP. |
| Animation Style | Snappy 2–4 frame loops. Inject: 2-frame squash. Swap: mold slides in 8-cycle visual. |
| VFX Style | Flat shapes + color, not particles-as-smoke. See §6. |
| Environment Style | One factory cell. Concrete-green floor, dark teal walls, no windows for MVP. |
| UI Graphic Style | Flat panels, 12px corner, no glass/blur. Status via color **and** icon/text. |

---

## 2. Mobile readability (non-negotiable)

- Silhouette of machine / hopper / bin / mold must be distinct at 64px.
- Contrast: status colors vs floor ≥ 4.5:1.
- **Never color-only.** Idle/Run/Swap/Cool also change icon + label.
- Defect vs good: red pip + "NG" mark, not red tint alone.
- Heat bar: fill color shifts idle→warn→danger, plus numeric.
- Interactive objects: 2px amber outline when tappable (future). MVP buttons live in HUD.

---

## 3. Locked palette

Hex, sRGB. Godot Color values in parentheses.

| Token | Hex | Godot | Use |
|---|---|---|---|
| bg | `#1A2229` | `Color(0.102, 0.133, 0.161)` | Screen behind factory |
| floor | `#3A4A3E` | `Color(0.227, 0.290, 0.243)` | Iso floor diamond |
| panel | `#1E2832` | `Color(0.118, 0.157, 0.196)` | HUD / sheets |
| ink | `#1A2229` | outline / text on light |
| paper | `#F4F1EA` | primary text on dark |
| machine_idle | `#47566B` | `Color(0.278, 0.337, 0.420)` | Line idle |
| machine_run | `#4A9FD4` | `Color(0.290, 0.624, 0.831)` | Injecting |
| machine_swap | `#E0A83A` | `Color(0.878, 0.659, 0.227)` | Mold swap |
| machine_cool | `#C45C5C` | `Color(0.769, 0.361, 0.361)` | Overheat / cooling |
| hopper | `#3D8C58` | resin / material |
| bin_empty | `#2A3340` | output bin empty |
| bin_good | `#3A7EC4` | output filling |
| defect | `#E25B4A` | NG units, fail toast |
| ok | `#5DD4A0` | success sheet, good pip |
| mold_cap | `#7EC4F0` | Bottle Cap mold |
| mold_case | `#5DD4A0` | Phone Case mold |
| mold_toy | `#E08BC0` | Toy Brick (locked) |
| tag_bulk | `#4A9FD4` | 대량 |
| tag_special | `#E0A83A` | 특수 |
| warn | `#E0A83A` | deadline / heat warn |

Heat bar: 0–60% `ok`, 61–85% `warn`, 86–100% `machine_cool`.

---

## 4. Camera / factory layout (portrait)

Viewport **720×1280**. Safe HUD:

- Top HUD: 118px (order / defect / balance). Keep below notch: extra 48px padding on device.
- Bottom controls: 210px. Touch target **≥ 44pt (~88px @ 2x)**.
- Factory stage: remaining center. Do not put tappable factory parts under thumbs.

Iso cell size: **256×256** px source for machine, hopper, bin, mold.  
On screen the machine should occupy ~160×160 logical px (readable, not HUD-covering).

---

## 5. Sprite / atlas spec (Godot)

Talk to Programmer before changing any of these.

| Item | Spec |
|---|---|
| Source | SVG → Godot import, or PNG @ 2x |
| Factory object | 256×256, pivot bottom-center (iso foot) |
| Mold block | 128×128, same pivot |
| HUD / order icon | 64×64 |
| App icon | 1024×1024 (store later). MVP uses `icon.svg` |
| Atlas | `factory_atlas.png` **1024×1024**, padding 2px, no rotation |
| Filter | `Nearest` off; use **Linear** + mipmaps off (clean cartoon) |
| Compress | Mobile: ETC2/ASTC (project already `vram_compression/import_etc2_astc=true`) |
| Max texture | 1024 for MVP atlas. Do not ship 4K plates. |
| Draw calls | One atlas for factory + molds. HUD icons may share `ui_atlas` 512×512. |
| Animation frames | Inject pulse: 2 frames. Swap: 1 slide (code tween OK). No 12-frame loops. |
| Particles | **0** in MVP. Heat/defect = ColorRect / modulate / 1 pip sprite. |
| Shader | None. Modulate only. |
| Polygon | N/A (2D). |

Placeholder files live in `res://assets/art/`. ColorRect remains valid fallback until TextureRects are wired.

---

## 6. State visualization (MVP P0)

Must be visible without opening a sheet.

| State | Machine | Extra |
|---|---|---|
| Idle | `machine_idle` | mold visible if installed |
| Injecting | `machine_run` + 2-frame squash | hopper pulse |
| Swapping | `machine_swap` | mold hidden or sliding |
| Cooling / overheat | `machine_cool` | heat bar danger |
| No mold | machine idle, mold slot empty (dark well) |
| Material low | hopper desaturate / low alpha (already in code) |
| Defect produced | red pip on bin for 2 frames + HUD defect % |

Gold / fail: success = sheet (`ok` header). Fail = toast (`defect` bg). Do not mix.

---

## 7. VFX (prototype budget)

Only information VFX:

- Inject success tick — small white flash on mold (1 frame)
- Defect — red `×` pip at bin
- Overheat — machine tint `machine_cool` (no fire particles)
- Settlement +cash — HUD balance punch scale
- Button — scale 0.96 (code)

No screen shake, no bloom, no smoke plumes.

---

## 8. Audio direction (MVP)

No BGM in prototype (loop fatigue on short sessions). SFX only on **decision / fail / money**:

| Event | Direction |
|---|---|
| Button | short tick, <80ms |
| Order accept | positive two-note |
| Order / action fail | muted down-blip |
| Mold swap complete | mechanical latch |
| Inject cycle | soft hiss, very quiet, duck if looping |
| Overheat stop | warning buzz once |
| Delivery OK | cash register |
| Settlement fail | dry thud |

Mix: SFX peak −12 dBFS. Mute toggle later (UI/UX).

---

## 9. MVP asset list (this pass)

P0 placeholders (SVG, shippable as-is):

1. `factory/machine.svg` — injection press, 256
2. `factory/hopper.svg` — resin hopper, 256
3. `factory/bin.svg` — output crate, 256
4. `factory/mold_cap.svg` / `mold_case.svg` / `mold_toy.svg` — 128
5. `factory/floor.svg` — iso diamond
6. `icons/tag_bulk.svg` / `tag_special.svg` — 64
7. `icons/hud_cash.svg` / `hud_defect.svg` — 64

P1 (after core loop verified on device): app icon, splash, 9-slice panel, heat icon.

Out of scope: staff, extra machines, R&D lab, outdoor world.

---

## 10. AI generation (if used later)

Always append: *clean cartoon isometric, 2:1 iso, 2px #1A2229 outline, flat top-left light, Injection Tycoon ART_BIBLE palette, no text, no watermark, mobile game asset, isolated on transparent, 256px subject, same camera as factory machine.*

Do not generate a new art style per asset.

---

## 11. Programmer contract

- Viewport stays 720×1280 portrait.
- State color tokens above replace magic Color() in `main.gd` when sprites land.
- Atlas: one `factory_atlas` 1024, filter linear, no custom shader.
- Particles count 0 / extra materials 0 until Art + Programmer agree.
- Unique node names (`Machine`, `Hopper`, `MoldBlock`, `OutputBin`) stay. Swap ColorRect → TextureRect + `modulate` is OK.

