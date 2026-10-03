# SkateGM

**Skate 3 in Garry's Mod.**

SkateGM runs Skate 3's board physics, tricks and scoring inside Garry's Mod,
on any map and with friends. It also comes with minigames, a park editor and
a gamemode built for skating.

It doesn't include anything from Skate 3. It reads the game files from your
own copy.

## What you need

- **Garry's Mod on the x86-64 branch.** In Steam, right-click Garry's Mod >
  Properties > Betas, and choose **x86-64**.
- **An Xbox-style controller.** Skating is controller only.
- **Your own copy of Skate 3 for the Xbox 360**, dumped by you as a folder
  that holds `default.xex`. If you have an `.iso`, extract it first, for
  example with extract-xiso.
- Windows.

## Install

1. Download **`SkateGM-Setup-<version>.exe`** from the
   [latest release](../../releases/latest).
2. Close Garry's Mod and run the installer.
3. Choose your Skate 3 **`default.xex`** and press **Install**.
   The installer finds Garry's Mod on its own; if it can't, choose the folder
   that has `garrysmod` inside. It converts your game files on your PC
   (nothing is downloaded) and installs the add-on and the engine module.

**To update**, run the new installer. Tick "Keep the game data I already
converted" to skip converting again. **To uninstall**, run the installer and
press **Uninstall**.

## Play

- **The SkateGM gamemode:** pick it from Garry's Mod's gamemode list, or
  load an `sgm_` map such as the included `sgm_warehouse`. Everyone skates
  all the time.
- **Any other gamemode:** open the console and type `bind j skategm_toggle`
  once. After that, J switches Skater mode on and off.

The first start takes a little while to load.

### Controls

Skate 3's own controls work as in the game. Hold **LB** to show the extras:

| Button | What it does |
|---|---|
| LB + D-pad down / up | Set a marker / hold to go back to it |
| LB + D-pad left | Minigames: host or join |
| LB + D-pad right | Players: spectate, teleport to, or join someone |
| LB + A | Settings: playermodel, board, camera, advanced |
| LB + Y | Map: look around and teleport |
| LB + B | Park editor |
| LB + X | Respawn |
| LB + RB | Replays |
| Right stick click (hold) | Rocket board, if it's on in Settings > Board |

### Minigames

Host one with LB + D-pad left; others join from the same menu.

| Minigame | How it plays |
|---|---|
| Race | Everyone starts together; first to the host's finish line wins. |
| Own the Spot | Take turns at one spot; the best-scoring turn owns it. |
| Hot Potato | Skate into someone to pass the ticking bomb. Whoever holds it when it blows loses a life; last one left wins. |
| Snake | Everyone leaves a glowing wall behind them. Hit a wall or the arena edge and you're out; orbs grow your tail. |
| Melon King | Grab the watermelon and hold it. Skate into the holder to steal it; bail and you drop it. First to the target time wins. |
| Trick Bingo | A shared 3x3 card of tricks and tasks. Land the lines that tick them off; three in a row wins. |
| Run Royale | Everyone skates a short run at once, then the runs are replayed and everyone votes out the worst. Last one left wins. |
| Hall of Meat | Take turns bailing as hard as you can. Every impact injures a body part; damage, injuries and air time add up to your score. |

Server owners can turn each one off in Settings > Advanced, or with
`skategm_<mode>_allowed 0`.

### Multiplayer

Everyone who wants to skate runs the installer on their own PC. A dedicated
server only needs the `skategm` add-on folder, from the release zip, in its
`garrysmod/addons`.

## Install by hand

If you'd rather not use the installer:

1. Unzip `skategm_<version>.zip`.
2. Put `gmcl_skategm_win64.dll` in `garrysmod/lua/bin`, making the `bin`
   folder if it isn't there.
3. Put the `skategm` folder in `garrysmod/addons`.
4. Convert your game files with Python 3:
   ```
   pip install numpy Pillow
   python exporter/convert.py --xex "D:/Games/Skate 3/default.xex" --out C:/skategm
   ```
   SkateGM looks for the data in `C:/skategm/assets`. If you put it
   somewhere else, type `skategm_data "your/folder/assets"` in the console.

## Building from source

The module is Rust (`gm_skategm/`, with the engine in `engine/`), built
for Windows with Rust 1.91.1 and MinGW-w64. The engine needs a few nightly
features, added by the rustc wrapper in `gm_skategm/build/`:

```
cd gm_skategm
rustc -O build/rwrap.rs -o build/rwrap.exe
RUSTC_BOOTSTRAP=1 RUSTC_WRAPPER=$PWD/build/rwrap.exe cargo build --release \
  --features engine --ignore-rust-version --target x86_64-pc-windows-gnu \
  -Zbuild-std=std,panic_unwind --lib
```

The add-on is plain Lua in `addon/skategm/`. To extend SkateGM from your own
add-on, see [minigames](docs/MODES.md), [board types and
effects](docs/BOARDS.md) and [park parts](docs/PARTS.md).

## A note on AI

SkateGM's code was written with the help of AI coding tools. I don't
support using generative AI for creative work like art, music, video, 3D
models, writing or game design, and I don't generally support giving AI free
rein over a project's structure and scaffolding either.

As a hobbyist indie game developer, I do not use generative AI for any
assets, nor for the game logic development, as I consider video games to be
pieces of art in every aspect, including the game logic.

Skate 3 itself is the work of the talented people at EA Black Box. This was
just a way to play it in multiplayer with my friends, and I thought I might
as well release it.

## Credits

SkateGM builds on others' open work:

- **[SK8-ENGINE/skate-3-rust-engine](https://github.com/SK8-ENGINE/skate-3-rust-engine)**:
  the Skate 3 engine reimplementation SkateGM runs, and the data exporter in
  `exporter/tools/` (commit `cb79689`).
- **[2010 Rust Rewrite Mashup](https://github.com/chasmlol/2010-rust-rewrite-mashup)**
  by chasmlol (Apache-2.0; a fork of [IW4L](https://github.com/vladtrc/iw4L)
  by vladtrc). The engine in `engine/` is its `skate/` folder with our changes
  ([`engine/README.md`](engine/README.md)), and `exporter/convert.py` is
  adapted from it.
- **Skate 3 Custom Engine Layer contributors** (MIT): the game archive readers
  in `exporter/tools/vendor/university` and `exporter/tools/owned_game`.
- **duckyinnit** (MIT): UTT, in `exporter/tools/vendor/utt`.
- **[chasmlol/skate-3-trick-toolkit](https://github.com/chasmlol/skate-3-trick-toolkit)**:
  the animation and skeleton decoders in `exporter/tools/vendor/skate3_anim`.

Each part's licence is listed in
[`LICENSE-THIRD-PARTY.md`](LICENSE-THIRD-PARTY.md).

SkateGM is a fan project, not affiliated with or endorsed by Electronic
Arts. No EA code or game data is included.
