"""Give a mapgen map a visible sun in its sky (gm_sk8): an env_sun set up as
gm_construct's, along the map's own light_environment (mapgen sets that from
Skate 3's sun direction). The entity lump is rewritten at the end of the
file, the old one left unused.

  python add_env_sun.py <map.bsp> [...]

The original is kept as <map>.bsp.before_sun.
"""
import re
import shutil
import struct
import sys
from pathlib import Path

LUMP_ENTITIES = 0

SUN = '''{{
"origin" "{origin}"
"use_angles" "1"
"size" "16"
"rendercolor" "241 240 199"
"pitch" "{pitch}"
"overlaysize" "-1"
"overlaymaterial" "sprites/light_glow02_add_noz"
"overlaycolor" "244 242 236"
"material" "sprites/light_glow02_add_noz"
"HDRColorScale" "1.0"
"angles" "{angles}"
"classname" "env_sun"
}}
'''


def patch(path):
    data = bytearray(Path(path).read_bytes())
    if data[:4] != b'VBSP':
        raise ValueError('not a BSP')
    offset, length = struct.unpack_from('<ii', data, 8 + LUMP_ENTITIES * 16)
    text = bytes(data[offset:offset + length]).rstrip(b'\0').decode('latin-1')
    if '"env_sun"' in text:
        return 'already has an env_sun'
    light = next((b for b in re.findall(r'\{[^{}]*\}', text) if '"light_environment"' in b), None)
    if light is None:
        return 'no light_environment to take the sun from'

    def key(name, default):
        m = re.search(r'"' + name + r'"\s*"([^"]*)"', light)
        return m.group(1) if m else default
    sun = SUN.format(origin=key('origin', '0 0 0'), pitch=key('pitch', '-50'), angles=key('angles', '0 0 0'))
    backup = Path(str(path) + '.before_sun')
    if not backup.exists():
        shutil.copyfile(path, backup)
    lump = (text + sun).encode('latin-1') + b'\0'
    while len(data) % 4:
        data.append(0)
    new_offset = len(data)
    data += lump
    struct.pack_into('<ii', data, 8 + LUMP_ENTITIES * 16, new_offset, len(lump))
    Path(path).write_bytes(data)
    return f'env_sun added (pitch {key("pitch", "-50")}, angles {key("angles", "0 0 0")})'


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(Path(p).name + ':', patch(p))
