"""Give already built Skate 3 maps their rails' retail splines and their
collision's native edges (gm_sk8).

mapgen used to store each rail as a polyline sampled from the game's spline;
SkateGM then ground on generic straight pieces. mapgen now also stores the
spline itself (SK3C version 2), which the module hands the engine as a .skate
package did. This adds that to maps built before, without rebuilding them:
it reads the map's skategm/skate3.json (district, frame) and skate3.sk3c,
reads the district's grind splines from your extracted Skate 3, matches each
rail by its two ends, and packs a version 2 skate3.sk3c back into the map.
A rail mapgen cut at the map's edge has no spline and stays a polyline.
Likewise each collision triangle gets back its edge codes and sidedness
(SK3C version 3): without them SkateGM's engine guessed every edge from
welded neighbours, and an edge between two pieces of a curved handrail's
tube came out sharp - the board caught on it.

  python update_bsp_rails.py --game <extracted Skate 3 (has data/)>
      --gmod <GarrysMod folder> <map.bsp> [<map.bsp> ...]

The original map is kept next to it as <map>.bsp.before_rails.
Needs Python 3 with numpy (Blender's bundled Python works).
"""
import argparse
import json
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

EXPORTER = Path(__file__).resolve().parent.parent / 'exporter'
sys.path.insert(0, str(EXPORTER))
from mapgen import MAP_TOOLS, skatecol  # noqa: E402
from mapgen.coords import Frame  # noqa: E402

sys.path.insert(0, str(MAP_TOOLS))


def sim_assets(game, district, tmp):
    from tools.owned_game.big import BigArchive
    from skate3_streams import load_district_stream
    big = BigArchive(Path(game) / f'data/content/world{district}.big')
    big.extract_entries([e for e in big.entries if 'Sim' in Path(e.path).name], tmp)
    folder = Path(tmp) / 'data/content/world/stream' / district
    return load_district_stream(folder, 'Sim', district)


def retail_edges(assets, frame):
    """Every collision triangle's packed surface (mapgen.scene.pack_surface),
    keyed by its corners as the map stores them (float32 bytes)."""
    from mapgen import scene
    rcm = scene._collision_module()
    out = {}
    for asset in assets:
        for mesh in rcm.decode_rx2_clustered_meshes(asset.data):
            one_sided = bool(mesh.mesh_flags & 0x10)
            for t in mesh.triangles:
                corners = frame.point(np.array([t.a, t.b, t.c], np.float32).astype(np.float64)).astype('<f4')
                out[corners.tobytes()] = scene.pack_surface(t.surface, t.edge_codes, one_sided)
    return out


def retail_rails(assets):
    """Every grind spline of a district: (start, end, native bytes)."""
    from retail_grind_splines import decode_grind_splines
    out = []
    for asset in assets:
        for rail in decode_grind_splines(asset.data):
            payloads = [bytes.fromhex(h) for h in rail['native_segment_payloads']]
            if not payloads or any(len(p) != 120 for p in payloads):
                continue
            first = np.frombuffer(payloads[0], '>f4')
            last = np.frombuffer(payloads[-1], '>f4')
            start = first[12:15].astype(np.float64)
            end = (last[0:3] + last[4:7] + last[8:11] + last[12:15]).astype(np.float64)
            # (as map_writer.py writes a .skate rail)
            native = struct.pack('<QQIII', int(rail['spline_id'], 0), int(rail['type_signature'], 0),
                                 int(rail['flags']), int(rail['trailing_word']), len(payloads))
            native += b''.join(np.frombuffer(p, '>u4').astype('<u4').tobytes() for p in payloads)
            out.append((start, end, native))
    return out


def update(bsp, game, gmod):
    bspzip = Path(gmod) / 'bin/bspzip.exe'
    gamedir = Path(gmod) / 'garrysmod'
    with tempfile.TemporaryDirectory(prefix='skategm_rails_') as tmp:
        tmp = Path(tmp)
        files = tmp / 'pak'
        subprocess.run([str(bspzip), '-game', str(gamedir), '-extractfiles', str(bsp), str(files)], check=True,
                       capture_output=True)
        info = json.loads((files / 'skategm/skate3.json').read_text(encoding='utf-8'))
        triangles, surfaces, rails = skatecol.decode((files / 'skategm/skate3.sk3c').read_bytes())
        frame = Frame(info['frame']['offset'], info['frame']['scale'])
        assets = sim_assets(game, info['district'], tmp / 'big')
        retail = retail_rails(assets)
        edges = retail_edges(assets, frame)
        surfaces = np.array(surfaces, np.uint64)
        tris = np.ascontiguousarray(triangles, '<f4')
        with_edges = 0
        for k in range(len(tris)):
            packed = edges.get(tris[k].tobytes())
            if packed is not None and packed & 0xFFFFFFFF == int(surfaces[k]) & 0xFFFFFFFF:
                surfaces[k] = packed
                with_edges += packed >> 56 & 1
        starts = frame.point(np.array([r[0] for r in retail])) if retail else np.zeros((0, 3))
        ends = frame.point(np.array([r[1] for r in retail])) if retail else np.zeros((0, 3))
        out, matched = [], 0
        for points, closed, native in rails:
            if native is None and len(points) >= 2:
                near = (np.abs(starts - points[0]).max(1) < 1.0) & (np.abs(ends - points[-1]).max(1) < 1.0)
                hit = np.flatnonzero(near)
                if len(hit):
                    native = retail[hit[0]][2]
            matched += native is not None
            out.append((points, closed, native))
        sk3c = tmp / 'skate3.sk3c'
        sk3c.write_bytes(skatecol.encode(triangles, surfaces, out))
        listing = tmp / 'list.txt'
        listing.write_text(f'skategm/skate3.sk3c\n{sk3c}\n', encoding='utf-8')
        packed = tmp / 'out.bsp'
        subprocess.run([str(bspzip), '-game', str(gamedir), '-addorupdatelist', str(bsp), str(listing), str(packed)],
                       check=True, capture_output=True)
        if not packed.is_file():
            raise RuntimeError('bspzip wrote nothing')
        backup = Path(str(bsp) + '.before_rails')
        if not backup.exists():
            shutil.copyfile(bsp, backup)
        shutil.copyfile(packed, bsp)
        print(f'{Path(bsp).name}: {matched} of {len(rails)} rails now carry Skate 3\'s own spline '
              f'({len(retail)} splines in {info["district"]}); {with_edges} of {len(tris)} collision triangles '
              f'carry their native edges')


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--game', required=True)
    p.add_argument('--gmod', required=True)
    p.add_argument('maps', nargs='+', type=Path)
    a = p.parse_args()
    failed = 0
    for bsp in a.maps:
        try:
            update(bsp, a.game, a.gmod)
        except Exception as e:  # one map failing leaves the others to do
            failed += 1
            print(f'{bsp.name}: failed: {e}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
