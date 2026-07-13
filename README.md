# TRS-80 Space Invaders

A faithful Space Invaders for the TRS-80 Model I and Model III, written in Z80
assembly. Runs on real hardware and in the [trs80gp](http://48k.ca/trs80gp.html)
emulator.

![Gameplay](assets/gameplay.gif)

## Features

- Full 5×11 invader formation with pixel-wise (not character-wise) marching and
  descent, flicker-free rendering on the 64×16 text screen
- Splash screen with arcade-style score table
- Mystery ship (UFO) with random 50–200 point bounty
- Four eroding shields with pixel-row erosion
- Per-kill speed-up — the last invader moves at ~14× the starting speed
- Wave progression: each wave starts lower and fires torpedoes 20% faster
- Sound: march bass loop, UFO blip, death sound (cassette port audio)
- Persistent high score across sessions (via `tools/play.py`)

| Splash | In game |
|---|---|
| ![Splash screen](assets/splash.png) | ![In game](assets/gameplay.png) |

## Play

```bash
# recommended: wrapper with persistent high score
tools/play.py

# or run directly (Model III)
trs80gp -m3 space_invaders.cmd
```

Arrow keys move, SPACE fires. Don't use `-turbo` — the game paces itself off
the frame rate. `space_invaders.cmd` is the prebuilt binary; it also loads on
a Model I (`-m1`).

## Build

Assembled with [zmac](http://48k.ca/zmac.html):

```bash
zmac space_invaders.asm            # -> zout/space_invaders.cmd
cp zout/space_invaders.cmd .
```

## The interesting part: byte-exact verification

This game was developed against two reference screenshots of the original it
recreates (`oldproj/StartGame.png`, `oldproj/StartGameOneMoveRight.png`).
Instead of eyeballing the screen, every change is validated by a pipeline that
proves the video RAM matches the targets **byte for byte**:

1. `tools/extract_grid.py` deterministically converts the reference PNGs into
   a 128×48 pixel matrix and the corresponding 64×16 character codes.
2. trs80gp runs headless (`-batch -turbo`), injects key presses through the
   keyboard matrix (`-ik`), and dumps raw text VRAM (`-it`) at precise frame
   counts.
3. `tools/verify.py` compares the dumps against the targets cell by cell.
4. `tools/validate_full.py` goes further: it detects the formation position on
   screen, reconstructs the *expected* full frame, and flags any residue pixel
   the incremental renderer left behind.

The 18 invader sprite variants (3 types × 2 animation states × 3 vertical
sub-positions) are not hand-drawn: `tools/gen_sprites.py` generates them from
the reference screenshots, which is what makes byte-exactness attainable.

## Architecture notes

- **One formation origin** (`FORM_COL/ROW/SUB/YSUB`) positions all 55 invaders —
  no per-invader address bookkeeping.
- `FORM_SUB` doubles as horizontal 1-pixel shift *and* animation state;
  `FORM_YSUB` gives 1-pixel vertical descent with character-row rollover.
- Sprites are blitted 5 characters wide with blank margins, so movement is
  self-cleaning: no erase pass, no flicker.
- Collision is resolved by screen peek plus back-calculation onto the
  formation slot.
- March speed comes from an 8.8 fixed-point speed table indexed by the live
  invader count, accumulated per frame.
- High score persistence abuses the printer port: on a new record the game
  prints `HSnnnn`, `tools/play.py` captures it and patches it back into the
  binary on next launch (works on Model I *and* III, which map the printer
  differently).
