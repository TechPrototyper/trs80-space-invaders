#!/usr/bin/env python3
"""Extract the 128x48 pixel matrix from a grid-snapped TRS-80 screenshot PNG.

The PNGs show the 128x48 block-graphics pixel grid with blue gridlines.
A cell is 'on' if its center is bright (white-ish).
Outputs: pixel matrix as text, plus the 64x16 character codes (128-191).
"""
import sys
from PIL import Image

def find_content_box(img):
    """Find the bounding box of the grid area (bright blue border lines)."""
    w, h = img.size
    px = img.load()
    # scan for leftmost/rightmost/top/bottom rows/cols containing blue grid or white
    def is_content(p):
        r, g, b = p[:3]
        return b > 80 and (b > r + 20)  # blue-ish
    left = right = top = bottom = None
    # sample the middle row/col
    midy, midx = h // 2, w // 2
    for x in range(w):
        if is_content(px[x, midy]):
            left = x; break
    for x in range(w - 1, -1, -1):
        if is_content(px[x, midy]):
            right = x; break
    for y in range(h):
        if is_content(px[midx, y]):
            top = y; break
    for y in range(h - 1, -1, -1):
        if is_content(px[midx, y]):
            bottom = y; break
    return left, top, right, bottom

def extract(path):
    img = Image.open(path).convert('RGB')
    l, t, r, b = find_content_box(img)
    px = img.load()
    W, H = 128, 48
    cw = (r - l + 1) / W
    ch = (b - t + 1) / H
    matrix = []
    for row in range(H):
        line = []
        for col in range(W):
            cx = l + (col + 0.5) * cw
            cy = t + (row + 0.5) * ch
            p = px[int(cx), int(cy)]
            bright = sum(p[:3]) / 3
            line.append(1 if bright > 140 else 0)
        matrix.append(line)
    return matrix

def to_chars(matrix):
    """Convert 128x48 pixel matrix to 16x64 char codes."""
    chars = []
    for crow in range(16):
        row = []
        for ccol in range(64):
            val = 128
            bit = 1
            for dy in range(3):
                for dx in range(2):
                    if matrix[crow * 3 + dy][ccol * 2 + dx]:
                        val += bit
                    bit <<= 1
            row.append(val)
        chars.append(row)
    return chars

if __name__ == '__main__':
    path = sys.argv[1]
    m = extract(path)
    print("PIXEL MATRIX (128x48):")
    for row in m:
        print(''.join('#' if v else '.' for v in row))
    print()
    print("CHAR CODES (64x16):")
    ch = to_chars(m)
    for r, row in enumerate(ch):
        nonblank = [(c, v) for c, v in enumerate(row) if v != 128]
        if nonblank:
            print(f"row {r:2d}: " + ' '.join(f"{c}:{v}" for c, v in nonblank))
