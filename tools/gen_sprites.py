#!/usr/bin/env python3
"""Generate all 18 sprite variants (3 types x 2 states x 3 y-shifts)
from the target screenshot pixel matrices. Emits zmac DB lines.
Layout: type*60 + state*30 + ysub*10; 5 bytes top row + 5 bytes bottom."""
from extract_grid import extract

m0 = extract('/Users/timw/Projects/z80test/oldproj/StartGame.png')
m1 = extract('/Users/timw/Projects/z80test/oldproj/StartGameOneMoveRight.png')

# 6x6 pixel window of the first invader of each type (char cols 13-15 = px 26-31)
# squid: char rows 1-2 (px 3-8), crab: rows 3-4 (px 9-14), octopus: rows 7-8 (px 21-26)
REGIONS = {0: 3, 1: 9, 2: 21}  # type -> top pixel row
NAMES = {0: 'squid', 1: 'crab', 2: 'octopus'}

def window(matrix, top):
    return [matrix[top + r][26:32] for r in range(6)]

def shift_down(win, n):
    return [[0]*6]*n + win[:6-n]

def to_char(win, crow, ccol):
    val, bit = 128, 1
    for dy in range(3):
        for dx in range(2):
            if win[crow*3 + dy][ccol*2 + dx]:
                val += bit
            bit <<= 1
    return val

def rows(win):
    top = [to_char(win, 0, c) for c in range(3)]
    bot = [to_char(win, 1, c) for c in range(3)]
    return top, bot

print("SPRITES:")
for t in range(3):
    print(f"; type {t} - {NAMES[t]}")
    for state, m in ((0, m0), (1, m1)):
        base = window(m, REGIONS[t])
        # sanity: bottom two pixel rows must be empty (4px tall sprite)
        assert not any(base[4]) and not any(base[5]), (t, state)
        for ysub in range(3):
            top, bot = rows(shift_down(base, ysub))
            fmt = lambda r: ','.join(str(v) for v in r)
            print(f"        DB      128,{fmt(top)},128,  128,{fmt(bot)},128    ; state {state} ysub {ysub}")
