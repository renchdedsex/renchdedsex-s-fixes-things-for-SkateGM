"""Stop Source forcing mat_fullbright on a mapgen map (gm_sk8).

mapgen's maps are all models: no brush face has a lightmap, so the BSP's
lighting lumps are empty, and the engine then forces mat_fullbright 1 -
which also turns off projected textures (SkateGM's sun). This gives the
map one texel of lighting data that no face uses: the world's own light
(the props' baked vertex light, the leaves' ambient light from vrad) is
unchanged, but the map now counts as lit.

  python unforce_fullbright.py <map.bsp> [...]

The original is kept as <map>.bsp.before_light.
"""
import shutil
import struct
import sys
from pathlib import Path

LUMP_LIGHTING = 8
LUMP_LIGHTING_HDR = 53
TEXEL = struct.pack('<BBBb', 128, 128, 128, 0)  # one ColorRGBExp32: mid grey


def patch(path):
    data = bytearray(Path(path).read_bytes())
    if data[:4] != b'VBSP':
        raise ValueError('not a BSP')

    def lump(i):
        return struct.unpack_from('<ii', data, 8 + i * 16)
    if lump(LUMP_LIGHTING)[1] > 0 or lump(LUMP_LIGHTING_HDR)[1] > 0:
        return 'already has lighting data'
    backup = Path(str(path) + '.before_light')
    if not backup.exists():
        shutil.copyfile(path, backup)
    while len(data) % 4:
        data.append(0)
    offset = len(data)
    data += TEXEL
    struct.pack_into('<ii', data, 8 + LUMP_LIGHTING * 16, offset, len(TEXEL))
    Path(path).write_bytes(data)
    return 'patched'


if __name__ == '__main__':
    for p in sys.argv[1:]:
        print(Path(p).name + ':', patch(p))
