"""Prepare Skate 3's own trick display for SkateGM (gm_sk8 addition).

Runs SK8-ENGINE/skate-3-rust-engine's tools/prepare_hud.py on your own
extracted Skate 3, then writes what Garry's Mod needs into
garrysmod/data/skategm_hud/:
  runtime/trickdisplay.json        the movie, for skategm.HudLoad
  <texture path>.png               each texture
  <texture path>.mask.png          its alpha as white (for the colour-add pass)

The output holds EA's assets from your copy of the game: keep it to yourself.

  python prepare_gmod_hud.py --engine <skate-3-rust-engine folder>
      --game <extracted Skate 3 (has data/)> --collections <.../private/stock/skater-collections.json>
      --gmod <GarrysMod folder>

Needs Python 3 with zlib (Blender's bundled Python works).
"""
import argparse
import json
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path


def png(path: Path, width: int, height: int, rgba: bytes):
    rows = b"".join(b"\x00" + rgba[y * width * 4:(y + 1) * width * 4] for y in range(height))

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--engine", type=Path, required=True)
    p.add_argument("--game", type=Path, required=True)
    p.add_argument("--collections", type=Path, required=True)
    p.add_argument("--gmod", type=Path, required=True)
    p.add_argument("--work", type=Path, help="where prepare_hud.py writes (default: a temporary folder)")
    p.add_argument("--vgmstream", type=Path, help="vgmstream-cli.exe: also decode the trick display's sounds (multiplier)")
    a = p.parse_args()
    work = a.work or Path(tempfile.mkdtemp(prefix="skategm_hud_"))
    subprocess.run([sys.executable, "prepare_hud.py", "--game", str(a.game), "--output", str(work),
                    "--collections", str(a.collections)], cwd=a.engine / "tools", check=True)
    movie = json.loads((work / "runtime/trickdisplay.json").read_text(encoding="utf-8"))
    out = a.gmod / "garrysmod/data/skategm_hud"
    (out / "runtime").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(work / "runtime/trickdisplay.json", out / "runtime/trickdisplay.json")
    textures = {}
    for shapes in movie["shapes"].values():
        for s in shapes:
            t = s["texture"]
            textures[t["rgba"]] = (t["width"], t["height"])
    # the fonts' atlases: their size from the preview PNG prepare_hud.py wrote
    for asset in movie.get("fonts", {}).values():
        if asset and asset.get("texture") and asset.get("preview"):
            head = (work / asset["preview"]).read_bytes()[16:24]
            textures.setdefault(asset["texture"], struct.unpack(">II", head))
    for rel, (w, h) in sorted(textures.items()):
        raw = (work / rel).read_bytes()
        if len(raw) != w * h * 4:
            print(f"skipped {rel}: {len(raw)} bytes for {w}x{h}")
            continue
        base = out / rel[:-len(".rgba")]
        png(base.with_name(base.name + ".png"), w, h, raw)
        mask = bytearray(raw)
        for i in range(0, len(mask), 4):
            mask[i] = mask[i + 1] = mask[i + 2] = 255
        png(base.with_name(base.name + ".mask.png"), w, h, bytes(mask))
        print("texture", rel, w, h)
    if a.vgmstream:
        sounds(a, out / "sound")
    print("Done:", out)


# The trick display's sounds: class `fe` records name a sound of the
# sk8_menu.bnk Splice bank (id >= record count: a container picking a record);
# a record's groups are layers played together. Each is mixed to one WAV.
FE_SOUNDS = ("multiplyer_2", "multiplyer_3")
# (seconds, gain) of each echo repeat
ECHO = ()
# seconds of linear fade-out at the end of each sound
FADE = 0.3


def sounds(a, out: Path):
    import importlib.util
    import wave
    sys.path.insert(0, str(a.engine / "tools"))
    from vendor.skate3_ui.big import BigArchive
    spec = importlib.util.spec_from_file_location("audio_formats", a.engine / "tools/asset_pipeline/audio_formats.py")
    af = importlib.util.module_from_spec(spec)
    sys.modules["audio_formats"] = af
    spec.loader.exec_module(af)
    big = BigArchive(a.game / "data/audio/audiofiles.big")
    bank = big.read(next(e for e in big.entries if e.path.endswith("sk8_menu.bnk")))
    patches, streams = af.splc_patches(bank), af.splc_streams(bank)
    records = json.loads(a.collections.read_text(encoding="utf-8"))["collections"]

    def field(r, h):
        return r["fields"].get(h, {}).get("data")
    fe = {field(r, "Hash_942AB8AEE4B414ED") or r["key"]: r for r in records if r["class"] == "fe"}
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)
        decoded = {}

        def sample(n):
            if n not in decoded:
                (tmp / f"{n}.snr").write_bytes(af.standalone(bank, streams[n]))
                subprocess.run([str(a.vgmstream), "-o", str(tmp / f"{n}.wav"), str(tmp / f"{n}.snr")], check=True, capture_output=True)
                with wave.open(str(tmp / f"{n}.wav")) as w:
                    decoded[n] = (w.getframerate(), w.getnchannels(), struct.unpack(f"<{w.getnframes() * w.getnchannels()}h", w.readframes(w.getnframes())))
            return decoded[n]
        for name in FE_SOUNDS:
            r = fe[name]
            sid = int(field(r, "Hash_8FCC7EF9B9208858"), 16)
            level = struct.unpack(">f", bytes.fromhex(field(r, "Hash_875BA75341DC8391") or "3F800000"))[0]
            rec = sid if sid < len(patches["records"]) else patches["containers"][sid - len(patches["records"])][0]
            mix, rate = [], 48000
            for group in patches["records"][rec]:
                n, gain = group["members"][0][0], group["members"][0][1]
                rate, ch, pcm = sample(n)
                mono = pcm[::ch]
                if len(mix) < len(mono):
                    mix += [0.0] * (len(mono) - len(mix))
                for i, v in enumerate(mono):
                    mix[i] += v * gain
            # a small echo (gm_sk8 addition, not in the game): delayed, quieter copies
            dry = list(mix)
            for delay, gain in ECHO:
                shift = int(rate * delay)
                if len(mix) < len(dry) + shift:
                    mix += [0.0] * (len(dry) + shift - len(mix))
                for i, v in enumerate(dry):
                    mix[i + shift] += v * gain
            fade = min(len(mix), int(rate * FADE))
            for k in range(fade):
                mix[len(mix) - fade + k] *= 1 - (k + 1) / fade
            peak = max(1.0, max(abs(v) for v in mix) / 32767)
            with wave.open(str(out / f"{name}.wav"), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(rate)
                w.writeframes(struct.pack(f"<{len(mix)}h", *(int(v / peak) for v in mix)))
            (out / f"{name}.txt").write_text(f"{level}\n")
            print("sound", name, "layers", len(patches["records"][rec]), "level", level)


if __name__ == "__main__":
    main()
