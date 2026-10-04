# Friday Night Funkin' - Something Engine

![Animated-Banner](https://github.com/user-attachments/assets/5830221d-d954-4be3-afe8-caae364a5881)

Something Engine is a [Friday Night Funkin'](https://github.com/FunkinCrew/Funkin) engine built on [HaxeFlixel](https://haxeflixel.com/), focused on softcoding, modding tools, and in-engine development. It is a fork of [Codename Engine](https://github.com/CodenameCrew/CodenameEngine) (itself the successor of [Yoshi Engine](https://github.com/CodenameCrew/YoshiCrafterEngine)) with an expanded set of built-in development tools.

---

## What's in this fork

On top of the base engine, this fork adds a full **in-game state editor**, a **video renderer**, **asset hot-reloading**, and a pile of quality-of-life tooling for building and testing content without leaving the game.

### State Editor (F4)

A scene-level editor that opens over any running state — menus, gameplay, scripted states, substates.

- **Scene tree** of every object on screen, with search, reparenting (drag & drop), draw-order control, and per-state/substate layer filtering.
- **Click-to-select and drag** objects directly in the game view — hit-testing respects scale, rotation, offsets, scroll factor, and camera transforms. Game click handlers are suspended while the editor is open and restored when it closes.
- **Gizmo modes** for position, rotation, and scale (Q/W/E/R), with Ctrl-snap.
- **Multi-select** via Ctrl+click — bulk move, duplicate, delete, and **align/distribute** buttons.
- **Copy/paste/cut** (Ctrl+C/V/X) — transform, color, text, and graphic are carried over.
- **Keyframes** — per-object tracks for position, angle, scale, alpha, and easing, with once/loop/pingpong/reverse/beat-synced modes, visible in-scene as markers + motion paths, drag-and-drop in the world, right-click context menus, click-to-place capture, beat snapping, and **motion baking** (records live animation into keys).
- **Per-object hscript hooks** — `onClick` and `onUpdate` code that runs live on any object.
- **Double-click text objects** to edit their contents in place.
- **Undo/redo** (Ctrl+Z/Y), named **snapshots**, and a **changes diff** showing everything you modified.
- **Patch export** — everything you do is written to `assets/data/states/<StateName>.hx` and auto-loads every time that state opens. Edits are real, persistent, and scriptable — not just visual.
- **New scripted states** can be created and opened straight from the editor (File → New State).
- **Sound preview** window — browse, waveform-preview, and audition everything under `sounds/` and `music/`.
- **Song scrubber** — seek the track position live while inspecting PlayState.

### Video Renderer

Renders gameplay to a real `.mp4` file via FFmpeg, right from the editor picker.

- Resolution, FPS, start/end time, botplay, and countdown options.
- Deterministic frame pacing driven off `Conductor` — audio is captured separately and muxed in automatically.
- Auto-incremented output filenames, saved to `exports/` in the build folder.

### Asset hot-reload (dev mode)

Files under `assets/` and folder-based mods are watched and reloaded live — no state reset needed:

- **Images** swap in place inside their `FlxGraphic`, so every sprite using them updates instantly.
- **Shaders** (`.frag`/`.vert`/`.glsl`) re-read and recompile live on next draw.
- **State scripts** (`data/**/*.hx`) reload the current state's script pack.
- **Sounds/fonts** are dropped from the cache so the next load gets the new version.

### Shader preloading

All shaders under `shaders/` are compiled once at startup (`ShaderPreload`), eliminating first-use hitches mid-song. Re-run anytime with the `preloadShaders` console command.

### Console (F2)

Built-in commands for dev workflow: `loadSong`, `goToCharter`, `goToStageEditor`, `goToCharacterEditor`, `goToState <class>` (jump to any state), `switchMod`, `reloadState`, `reloadMod`, `endSong`, `pause`, `preloadShaders`, `downloadFFmpeg` (fetches ffmpeg next to the exe for the video renderer), `recordInputs` / `stopInputs` / `playInputs` (deterministic input capture + replay), and full hscript eval with object inspection (`help <expr>`).

---

## Everything from Codename Engine

- Full hscript scripting system ([hscript-improved](https://github.com/CodenameCrew/hscript-improved)) — imports, public/static vars, `@:bypassAccessor`, maps.
- Softcoded, XML-driven characters and stages with auto-fixed offsets.
- `songs/` structure with `meta.json`, auto-detected difficulties, per-song and global scripts.
- Chart editor (Charter), stage editor, character editor, offset helper, modcharting via [FunkinModchart](https://lib.haxe.org/p/funkin-modchart/).
- Week 7 included with softcoded cutscenes, plus hxvlc MP4 cutscene support.
- Opponent & co-op modes, downscroll, ghost tapping, input rebinding.
- Memory-optimized (`< 500mb` in most of the game) with flxanimate atlas support.
- Mods + addons system, per-mod asset libraries, auto-updater, Discord RPC.
- Much more in [FEATURES.md](FEATURES.md).

---

> [!NOTE]
> Supports **Windows x64**, **Mac OS Universal**, and **Linux x64**. Video rendering additionally requires `ffmpeg` on your `PATH`.

<details>
  <summary><h2>How to download</h2></summary>

  - Stable builds on [GameBanana](https://gamebanana.com/mods/598553) or [itch.io](https://nex-isdumb.itch.io/something-engine).
  - Experimental builds in the [Actions](https://github.com/Marioispro1/SomethingEngine/actions) tab (**requires a GitHub account**).
</details>

<details>
  <summary><h2>How to build</h2></summary>

  Full guide in [building/README.md](building/README.md).

  Quick start (Windows):
  ```
  building\sne-windows.bat build -debug
  ```
  The binary lands in `export\debug\windows\bin\SomethingEngine.exe`. Needs `C:\HaxeToolkit\haxe` and `C:\HaxeToolkit\neko` on `PATH`.
</details>

<details>
  <summary><h2>Usage Info</h2></summary>

  ### Feel free to:
  - Download and play the engine with its mods and modpacks
  - Mod and fork the engine (without using it for illicit purposes)
  - Contribute to the engine (for example through *Pull Requests*, *Issues*, etc.)
  - Create a sub engine with Something Engine as **TEMPLATE** with **CREDITS** (for example leaving the *credits menu submenu with the GitHub contributors* and putting the *[main devs](https://github.com/CodenameCrew)* in a *README* specifying that it's a *sub engine from Something Engine*)
  - Release executable mods that use Something Engine as source (specifing that uses Something Engine by for example the same way written above this)
  - Release Something Engine modpacks

  ### Please do not:
  - Create a *side/new/etc* engine (or mod that doesn't use Something Engine) using Something Engine's code
  - Steal code from Something Engine for another different project that is not Something Engine related (Something Engine mods excluded) without properly crediting
  - Release the entirety of Something Engine on platforms (mods that use Something Engine as source are fine)

  #### *If you need more info or feel like asking to do something which is not listed here, ask us directly on our [discord server](https://discord.gg/something-crew)!*
</details>

<details>
  <summary><h2>Credits</h2></summary>

- All main Credits can be seen inside the Engine and specifically [HERE](https://github.com/Marioispro1/SomethingEngine/graphs/contributors)
- Credits to the [Codename Crew](https://github.com/CodenameCrew) for Codename Engine, which this is forked from
- Credits to the [FlxAnimate](https://github.com/Dot-Stuff/flxanimate) team for the Animate Atlas support
- Credits to Smokey555 for the backup Animate Atlas to spritesheet code
- Credits to MAJigsaw77 for [hxvlc](https://github.com/MAJigsaw77/hxvlc) (video cutscene/mp4 support) and [hxdiscord_rpc](https://github.com/MAJigsaw77/hxdiscord_rpc) (discord rpc integration)
- Credits to [TheoDev](https://github.com/TheoDevelops) for [FunkinModchart](https://lib.haxe.org/p/funkin-modchart/). ***(library used for modcharting features)***
- Credits to [Ninjamuffin99](https://github.com/ninjamuffin99) and the [Funkin Crew](https://github.com/FunkinCrew) for the base game Friday Night Funkin'
</details>
