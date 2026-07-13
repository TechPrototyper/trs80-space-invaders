#!/usr/bin/env python3
"""Full-screen validation: reconstruct the expected screen from the
detected formation position and compare cell-by-cell.
Flags any residue/garbage the incremental rendering left behind."""
import os
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
import glob, sys
from extract_grid import extract

m0 = extract(os.path.join(_ROOT, 'oldproj/StartGame.png'))
m1 = extract(os.path.join(_ROOT, 'oldproj/StartGameOneMoveRight.png'))

REGIONS = {0: 3, 1: 9, 2: 21}
def window(m, top): return [m[top+r][26:32] for r in range(6)]
def shift(w, n): return [[0]*6]*n + w[:6-n]
def chars(w):
    out = []
    for cr in range(2):
        row = []
        for cc in range(3):
            v, bit = 128, 1
            for dy in range(3):
                for dx in range(2):
                    if w[cr*3+dy][cc*2+dx]: v += bit
                    bit <<= 1
            row.append(v)
        out.append(row)
    return out

TMPL = {}  # (type,state,ysub) -> [[top3],[bot3]]
for t in range(3):
    for s, m in ((0, m0), (1, m1)):
        for y in range(3):
            TMPL[(t, s, y)] = chars(shift(window(m, REGIONS[t]), y))

ROW_TYPE = [0, 1, 1, 2, 2]
SHIELD_A = [[128,176,176,176,144,128],[191,191,143,175,191,149]]
SHIELD_B = [[128,160,176,176,176,128],[170,191,159,143,191,191]]
PLAYER = [160,184,176]

def build_expected(fcol, frow, state, ysub, alive, player_x, shields):
    scr = [[128]*64 for _ in range(16)]
    for k in range(5):
        t = ROW_TYPE[k]
        tm = TMPL[(t, state, ysub)]
        for f in range(11):
            if not alive[k*11+f]: continue
            r, c = frow + 2*k, fcol + 4*f
            for dr in range(2):
                for dc in range(3):
                    scr[r+dr][c+dc] = tm[dr][dc]
    for base, sh in shields:
        for dr in range(2):
            for dc in range(6):
                scr[13+dr][base+dc] = sh[dr][dc]
    for dc in range(3):
        scr[15][player_x+dc] = PLAYER[dc]
    return scr

def analyze(path):
    d = open(path, 'rb').read()
    grid = [list(d[r*64:(r+1)*64]) for r in range(16)]
    # locate formation: try every (fcol,frow,state,ysub) and count matching
    # squid top-left won't work when leftmost column is dead; brute force.
    best = None
    for frow in range(1, 5):
        for fcol in range(1, 21):
            for s in range(2):
                for y in range(3):
                    # score against all invader cells assuming all alive
                    m = 0; tot = 0
                    for k in range(5):
                        tm = TMPL[(ROW_TYPE[k], s, y)]
                        for f in range(11):
                            for dr in range(2):
                                for dc in range(3):
                                    tot += 1
                                    if grid[frow+2*k+dr][fcol+4*f+dc] == tm[dr][dc]:
                                        m += 1
                    if best is None or m > best[0]:
                        best = (m, fcol, frow, s, y)
    _, fcol, frow, s, y = best
    # determine alive flags per slot
    alive = []
    for k in range(5):
        tm = TMPL[(ROW_TYPE[k], s, y)]
        for f in range(11):
            cells = [grid[frow+2*k+dr][fcol+4*f+dc] for dr in range(2) for dc in range(3)]
            want = [tm[dr][dc] for dr in range(2) for dc in range(3)]
            alive.append(1 if cells == want else 0)
    # player
    pcols = [c for c in range(64) if grid[15][c] != 128]
    px = pcols[0] if pcols else None
    # shields: take rows 13/14 as-is (they erode); treat as matching by copying
    shields = []
    exp = build_expected(fcol, frow, s, y, alive, px if px is not None else 24, shields)
    # copy observed shield rows into expected where formation didn't reach
    diffs = []
    for r in range(1, 16):
        for c in range(64):
            g = grid[r][c]
            e = exp[r][c]
            if r in (13, 14):
                continue  # shields erode: skip strict check
            if g in (149, 170) and e == 128:
                continue  # projectile in flight
            if g != e:
                diffs.append((r, c, g, e))
    n_alive = sum(alive)
    print(f"{path}: form=({fcol},{frow}) state={s} ysub={y} alive={n_alive} "
          f"score_cells_match={best[0]}/330 player_x={px} diffs={len(diffs)}")
    for x in diffs[:12]:
        print("   residue:", x)

for p in sorted(glob.glob('trs80-text-*.bin'), key=lambda s: int(s.split('-')[-1].split('.')[0])):
    analyze(p)
