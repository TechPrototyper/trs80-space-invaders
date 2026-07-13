#!/usr/bin/env python3
"""Launch Space Invaders with a persistent high score.

The game prints "HSnnnn\r" to the printer whenever a new high score is
set at game over. This script:
  1. reads hiscore.dat (repo root; plain 4-digit text),
  2. patches those digits into HISCORE_D inside a temp copy of the
     release space_invaders.cmd (address taken from zout/space_invaders.bds),
  3. runs trs80gp with the printer captured to a file,
  4. harvests the highest HSnnnn from the capture back into hiscore.dat.

Usage: tools/play.py [extra trs80gp args]        (e.g. -m1, -vol 50)
"""
import pathlib
import re
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
CMD = ROOT / 'space_invaders.cmd'
BDS = ROOT / 'zout' / 'space_invaders.bds'
HISCORE = ROOT / 'hiscore.dat'
EMU = '/Applications/trs80gp.app/Contents/MacOS/trs80gp'


def read_hiscore():
    try:
        text = HISCORE.read_text().strip()
        if re.fullmatch(r'\d{1,4}', text):
            return int(text)
    except FileNotFoundError:
        pass
    return 0


def symbol_addr(name):
    pat = re.compile(rf'^([0-9a-f]{{4}}) [0-9a-f]{{4}} s {re.escape(name)}:')
    for line in BDS.open():
        m = pat.match(line)
        if m:
            return int(m.group(1), 16)
    raise SystemExit(f'symbol {name} not found in {BDS}')


def patch_cmd(data: bytes, addr: int, values: bytes) -> bytes:
    """Patch bytes at Z80 address addr inside a TRS-80 /CMD image."""
    out = bytearray(data)
    i = 0
    while i < len(out):
        rtype = out[i]
        length = out[i + 1]
        if rtype == 0x01:                      # load record
            count = length if length >= 3 else length + 256
            load = out[i + 2] | (out[i + 3] << 8)
            body = i + 4                       # file offset of first data byte
            ndata = count - 2
            for k, v in enumerate(values):
                off = addr + k - load
                if 0 <= off < ndata:
                    out[body + off] = v
            i = body + ndata
        elif rtype == 0x02:                    # entry point: last record
            break
        else:                                  # named/other: skip payload
            i += 2 + (length if length else 256)
    return bytes(out)


def main():
    hiscore = read_hiscore()
    digits = bytes(int(d) for d in f'{hiscore:04d}')
    addr = symbol_addr('HISCORE_D')
    patched = patch_cmd(CMD.read_bytes(), addr, digits)

    with tempfile.TemporaryDirectory(prefix='si_hiscore_') as tmp:
        tmp = pathlib.Path(tmp)
        game = tmp / 'space_invaders.cmd'
        game.write_bytes(patched)
        capture = tmp / 'printer.out'
        argv = [EMU, '-m3', '-p', f'>{capture}', str(game)] + sys.argv[1:]
        subprocess.run(argv)
        try:
            raw = capture.read_bytes()
        except FileNotFoundError:
            raw = b''

    best = max((int(m.group(1)) for m in re.finditer(rb'HS(\d{4})', raw)),
               default=0)
    if best > hiscore:
        HISCORE.write_text(f'{best:04d}\n')
        print(f'new high score saved: {best:04d}')
    elif hiscore:
        print(f'high score stays at {hiscore:04d}')


if __name__ == '__main__':
    main()
