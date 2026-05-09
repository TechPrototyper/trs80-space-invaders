# Space Invaders Clone (TRS-80 Model I/III)

This is a simple Space Invaders clone written in Z80 assembly language for the TRS-80 Model I and Model III.

## Features
- **Graphics**: Uses the TRS-80's 128x48 block graphics mode (characters 128-191).
- **Sound**: Includes "iconic" pew-pew and explosion sounds using the cassette port (Port 0xFF).
- **Controls**:
  - **Left Arrow**: Move Left
  - **Right Arrow**: Move Right
  - **Space Bar**: Fire

## How to Assemble with zmac
Since you are using `zmac`, it will automatically generate a valid TRS-80 `.cmd` file.

### Command Line
```bash
zmac space_invaders.asm
```
This will typically create `zout/space_invaders.cmd` (or just `space_invaders.cmd` depending on your version/configuration).

### Loading in trs80gp
1. Locate the generated `.cmd` file.
2. Load it directly into `trs80gp`.
   - You can drag and drop the `.cmd` file into the emulator window.
   - Or run it from the command line: `trs80gp space_invaders.cmd`
3. The program is set to auto-execute (via the `END START` directive).

## Code Structure
- `START`: Initialization and main loop.
- `READ_KEYS`: Scans the keyboard matrix directly.
- `UPDATE_*`: Handles movement logic for the player, bullet, and aliens.
- `DRAW_*`: Renders the game objects using block graphics characters.
- `SFX_*`: Sound effect routines toggling Port 0xFF.
