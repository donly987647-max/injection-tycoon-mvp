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


## Play in browser (GitHub Pages)

**HTTPS play URL:** https://donly987647-max.github.io/injection-tycoon-mvp/

Web export is published from the `gh-pages` branch (`build/web/*`, Godot HTML5).  
`variant/thread_support=false` so the build runs on GitHub Pages without COOP/COEP headers.

Rebuild web locally:

```bash
/workspace/injection-tycoon-mvp/scripts/export_web.sh
# then zip: python3 scripts/zip_web.py
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
3. **Injection** — each cycle is **1 shot → 1 unit** (material 1/shot) at `defect_rate` (default **12%**, conceptual range 5%–35%). Fail-stop (toast) on **overheat** (`max_heat` **80**, cool **−5**/idle cycle) or **material shortage**.
4. **Delivery** — success if `good_units >= order.qty` **and** `cycle <= deadline`. Else fail toast.
5. **Settlement** — success credits `reward`. Late / fail applies **−40% of reward** (`penalty`). Shortage = no delivery / fail. Excess defects (> 15%) also fail. Autosave on settle.

HUD always shows **order summary, defect rate, balance** (plus cycle and resin).

## MVP balance (Game Design sheet)

Locked numbers used by this prototype (cycle ≈ 1s of design time for deadlines/swap):

| Item | Value |
|------|-------|
| Shot / cycle | 1 unit, material 1 per shot |
| Overheat | `line.max_heat = 80` |
| Cooling | −5 heat per idle/cooling cycle |
| Mold swap | **8** cycles (not while running) |
| Defect rate | start **0.12** (usable 5%–35%; single rate until pressure/temp) |
| Starting balance | **500** |
| Orders (fixed board) | tutorial 20 / lead 120 / $150 / pen 0; bulk 100 / 180 / $300 / 40%; special 30 / 90 / $500 / 40% |
| Late settlement | **−40%** of reward |
| Shortage | no delivery / fail |

Optional upgrade stubs (not required this pass): speed −0.5s ($200), cool +2 ($150), mold slot +1 ($400).

## Save

- Path: `user://save_v1.json` (version `1`)
- Autosave on **settlement**, window **close**, and **application pause**
- Reset (R) deletes the save and starts a new factory

`user://` on desktop is typically:

- Linux: `~/.local/share/godot/app_userdata/Injection Tycoon MVP/`
- Headless smoke in this environment: `$HOME/.local/share/godot/app_userdata/Injection Tycoon MVP/save_v1.json`

## Android export

Debug APK path: `build/InjectionTycoonMVP-debug.apk` (~28 MiB after rebuild; gitignored under `build/`)  
Package: `com.injectiontycoon.mvp` · portrait · `arm64-v8a` · non-Gradle template export.

### One-shot rebuild (this environment)

```bash
/workspace/injection-tycoon-mvp/scripts/export_android_debug.sh
```

Or manually:

```bash
export PATH="/workspace/tools/bin:$PATH"
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/workspace/tools/android-sdk
export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
mkdir -p /workspace/injection-tycoon-mvp/build
godot --headless --path /workspace/injection-tycoon-mvp \
  --export-debug "Android" /workspace/injection-tycoon-mvp/build/InjectionTycoonMVP-debug.apk
```

### What was installed (box paths)

| Component | Location |
|-----------|----------|
| Godot 4.7.2 | `/workspace/tools/bin/godot` |
| OpenJDK 21 | `/usr/lib/jvm/java-21-openjdk-amd64` |
| Android SDK | `/workspace/tools/android-sdk` (cmdline-tools, platform-tools, platforms;android-35+36, build-tools;35.0.0 / 35.0.1 / 36.0.0) |
| Export templates | `~/.local/share/godot/export_templates/4.7.2.stable/` (`android_debug.apk`, `android_release.apk`) |
| Debug keystore | `android/debug.keystore` (alias `androiddebugkey`, store/key pass `android`) |
| Export preset | `export_presets.cfg` preset name **Android** |

Editor settings (user account): `~/.config/godot/editor_settings-4.7.tres` points Java/Android SDK + debug keystore at the paths above.

### Fresh machine setup

1. **JDK** — OpenJDK 17+ (box uses 21). Set `JAVA_HOME`.
2. **Android SDK** under `/workspace/tools/android-sdk` (or your path):
   ```bash
   # unpack Google commandlinetools into $ANDROID_HOME/cmdline-tools/latest
   yes | sdkmanager --licenses
   sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;36.0.0"
   ```
3. **Export templates** — download `Godot_v4.7.2-stable_export_templates.tpz` from the [4.7.2 release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable), unzip into `~/.local/share/godot/export_templates/4.7.2.stable/` (must contain `android_debug.apk` and `version.txt` = `4.7.2.stable`).
4. **Editor Settings → Export → Android** — set Java SDK Path + Android SDK Path; debug keystore as above (or leave blank to use editor defaults).
5. Open the project once so assets import, then run the rebuild script / `--export-debug`.

Portrait is set in `project.godot` (`window/handheld/orientation=1`). Renderer is **mobile**. NDK/CMake are **not** required for this non-Gradle APK path; they are needed only if you enable **Gradle Build** / custom Android builds / AAB for Play Store.

### Sideload

```bash
adb install -r build/InjectionTycoonMVP-debug.apk
```

Release / Play Store needs a non-debug keystore, usually Gradle + AAB — out of scope for this MVP debug path.

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
