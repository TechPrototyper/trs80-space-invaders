#!/usr/bin/env python3
"""Compare emulator VRAM dumps against target screenshots (rows 1-15,
cols 5-63). Row 0 is the UFO lane; cols 0-4 are the status sidebar
(SCORE/P1/reserve ships) - neither exists in the target images."""
import sys
sys.path.insert(0, '.')
from extract_grid import extract, to_chars

def load_dump(path):
    data = open(path, 'rb').read()
    return [list(data[r*64:(r+1)*64]) for r in range(16)]

def show(grid, label):
    print(f"--- {label} ---")
    for r, row in enumerate(grid):
        nb = [(c, v) for c, v in enumerate(row) if v != 128 and v != 32]
        if nb:
            print(f"row {r:2d}: " + ' '.join(f"{c}:{v}" for c, v in nb))

def compare(dump, target, label):
    diffs = []
    for r in range(1, 16):
        for c in range(5, 64):
            d, t = dump[r][c], target[r][c]
            if d == 32: d = 128  # space renders identical to blank graphics char
            if t == 32: t = 128
            if d != t:
                diffs.append((r, c, d, t))
    if not diffs:
        print(f"{label}: EXACT MATCH (rows 1-15)")
    else:
        print(f"{label}: {len(diffs)} diffs")
        for r, c, d, t in diffs[:40]:
            print(f"  row {r} col {c}: got {d}, want {t}")
    return not diffs

t_start = to_chars(extract('/Users/timw/Projects/z80test/oldproj/StartGame.png'))
t_move1 = to_chars(extract('/Users/timw/Projects/z80test/oldproj/StartGameOneMoveRight.png'))

dumps = [load_dump(f'trs80-text-{i}.bin') for i in range(5)]

# Identify which dumps match which state
for i, d in enumerate(dumps):
    m0 = sum(1 for r in range(1, 16) for c in range(5, 64) if d[r][c] == t_start[r][c])
    m1 = sum(1 for r in range(1, 16) for c in range(5, 64) if d[r][c] == t_move1[r][c])
    print(f"dump {i}: match-vs-start {m0}/885, match-vs-move1 {m1}/885")

print()
compare(dumps[0], t_start, "dump0 vs StartGame")
print()
compare(dumps[1], t_move1, "dump1 vs OneMoveRight")
print()
show(dumps[0], "dump0 row0 (HUD)")
