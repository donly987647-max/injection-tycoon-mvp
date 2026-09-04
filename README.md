# Injection Tycoon MVP

Mobile-oriented **Godot 4** prototype of a one-line plastic injection factory.

Core loop: **Order → Mold swap → Injection + defects → Delivery → Settlement**.

No staff, R&D, or multi-plant. Cartoon isometric placeholders (ColorRects) — no art pack required.

## Requirements

- Godot **4.3+** (developed with **4.7.2** stable)
- Linux / macOS / Windows editor, or headless for smoke

If you used the box install:

```bash
export PATH="/workspace/tools/bin:$PATH"
godot --version   # 4.7.2.stable.official
```

## Open / run

1. Launch Godot 4.x
2. **Import** → select `/workspace/injection-tycoon-mvp/project.godot`
3. Press **F5** (or Run)

Command line (desktop window):

```bash
godot --path /workspace/injection-tycoon-mvp
```

Headless load check:

```bash
godot --headless --path /workspace/injection-tycoon-mvp --quit-after 2
```

Smoke (happy path + fail branches + save file):

```bash
godot --headless --path /workspace/injection-tycoon-mvp res://scenes/smoke.tscn
```

## How to play (desktop)

Portrait 720×1280, mouse emulates touch. Keyboard:

| Key | Action |
|-----|--------|
| O | Order board |
| M | Mold swap |
| I | Start injection |
| S | Stop line |
| C / N | Advance 1 cycle |
| D | Deliver + settle |
| B | Buy resin |
| R | Reset save |

**Happy path**

1. **Orders** → Accept a **Bottle Cap** job that is **not** near-deadline (deadline ≤ 1 cycle fails).
2. **Molds** → Swap in **Bottle Cap Mold** (owned). Advance cycles until the success sheet.
3. **Inject**, then **Cycle** until good units ≥ qty (watch heat / resin).
4. **Deliver**. Success sheet credits the reward and **autosaves**.

### Success / fail rules

1. **Order** — accept if the single slot is free and remaining cycles **> 1**. Fail toast if slot full, or if the job is near-deadline (`deadline - cycle <= 1`). Rejecting a near-deadline job is also a fail toast.
2. **Mold swap** — starts if the line is idle and the mold is owned; completes after `swap_time` cycles (success sheet). Fail if the line is running or the mold is not owned (Toy Brick is locked).
3. **Injection** — each cycle produces 10 shots at `defect_rate` (HUD). Fail-stop (toast) on **overheat** or **material shortage**.
4. **Delivery** — success if `good_units >= order.qty` **and** `cycle <= deadline`. Else fail toast.
5. **Settlement** — success credits `reward`. Fail applies `penalty` if late, short, or **excess defects** (> 15% of shots). Autosave on settle.

HUD always shows **order summary, defect rate, balance** (plus cycle and resin).

## Save

- Path: `user://save_v1.json` (version `1`)
- Autosave on **settlement**, window **close**, and **application pause**
- Reset (R) deletes the save and starts a new factory

`user://` on desktop is typically:

- Linux: `~/.local/share/godot/app_userdata/Injection Tycoon MVP/`
- Headless smoke in this environment: `$HOME/.local/share/godot/app_userdata/Injection Tycoon MVP/save_v1.json`

## Android export (brief)

1. In Godot: **Editor → Manage Export Templates** → download templates matching the editor version (4.7.2).
2. **Project → Export → Add → Android**.
3. Install Android SDK / NDK / JDK as [official docs](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html).
4. Use **Gradle Build** for a debug APK. Portrait is already set (`window/handheld/orientation=1` / portrait), renderer **mobile**, touch-from-mouse on for editor play.
5. Set package name (e.g. `com.injectiontycoon.mvp`) and launcher icons before a store build.

This MVP does not ship export templates or a signed keystore.

## Layout

```
project.godot
scenes/main.tscn          # factory placeholder + HUD + panels
scripts/autoload/game_state.gd
scripts/models/{order,mold,line_state}.gd
scripts/ui/{toast,sheet,order_board,mold_panel}.gd
scripts/main.gd
scripts/smoke_test.gd
```

## Out of scope (placeholders)

- Art / true isometric tiles (ColorRect machine, hopper, bin)
- Staff, R&D, multi-line / multi-plant
- Unlocking the Toy Brick mold
- Sound, tutorials, IAP
