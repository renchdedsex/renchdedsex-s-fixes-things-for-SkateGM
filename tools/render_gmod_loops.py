"""Skate 3's held skate sounds rendered through its own audio engine (AEMS,
skate-3-rust-engine's skate-audio, example aems_render) for SkateGM (gm_sk8).

Each class is posted with the words the game's player component writes while
it holds the sound (skate-audio/src/player/components.rs), at a few speeds,
rendered, cut into a seamless loop and written next to prepare_gmod_sounds.py's
output (garrysmod/addons/skategm_s3sounds/sound/skate3/loops/):
  grind/<surface>_<layer>_<speed>.wav   Class_grind: surface 0..13, layer 0..3
                                        (layer "01" = family 0: layers 2 + 1 mixed)
  skid/<surface>_<speed>.wav            Class_wheels_skid (powerslide), surface 0..4
  drag/<surface>_<speed>.wav            Class_foot_drag (foot braking), surface 0..10
speed: 0 slow, 1 medium, 2 fast.

  python render_gmod_loops.py --engine <skate-3-rust-engine> --work <AEMS folder: .csi, csi_order.txt,
      .abk, audio/banks/<stem>/NNNN.wav> --gmod <GarrysMod>
"""
import argparse
import importlib.util
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prepare_gmod_sounds as prep  # noqa: E402

SPEEDS = (1500, 5000, 9000)
SECONDS = 6


def grind_words(surface, layer, speed):
    return [32767, 32767, 0, 0, 4096, 25000, 25000, speed, 1024, surface, layer, 32767, 0, 1, 1, 0, 5]


def skid_words(surface, speed):
    return [32767, 32767, 0, 0, 4096, 25000, 25000, speed, 0, surface, 60, 23000, 32767, 0, 1, 1, 0, 5]


def drag_words(surface, speed):
    return [32767, 32767, 0, 0, 4096, 25000, 0, speed, surface, 4000, 4500, 4000, 22500, 0, 7]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--engine', type=Path, required=True)
    p.add_argument('--work', type=Path, required=True)
    p.add_argument('--gmod', type=Path, required=True)
    a = p.parse_args()
    exe = a.engine / 'target/release/examples/aems_render.exe'
    spec = importlib.util.spec_from_file_location('audio_formats', a.engine / 'tools/asset_pipeline/audio_formats.py')
    af = importlib.util.module_from_spec(spec)
    sys.modules['audio_formats'] = af
    spec.loader.exec_module(af)
    out = a.gmod / 'garrysmod/addons/skategm_s3sounds/sound/skate3/loops'

    def render(tmp, bank, cls, words):
        wav = tmp / 'r.wav'
        r = subprocess.run([str(exe), str(a.work), str(a.work / 'audio'), bank, cls, ','.join(map(str, words)),
                            str(SECONDS), str(wav)], capture_output=True, text=True)
        if r.returncode != 0 or not wav.is_file():
            return None
        with wave.open(str(wav)) as w:
            frames = w.readframes(w.getnframes())
        pcm = struct.unpack(f'<{len(frames) // 2}h', frames)
        # stereo -> mono, skipping the first second (attack)
        mono = [(pcm[i] + pcm[i + 1]) / 2 for i in range(2 * 48000, len(pcm) - 1, 2)]
        return mono

    def loop_of(mono):
        if not mono or max(abs(v) for v in mono) < 30:
            return None
        frames = struct.pack(f'<{len(mono)}h', *(int(max(-32768, min(32767, v))) for v in mono))
        band = af.loop_bands(frames, 1, round(0.08 * 48000))[0]
        return list(struct.unpack(f'<{len(band) // 2}h', band))

    def save(path, mono):
        lp = loop_of(mono)
        if lp:
            prep.write_wav(path, 48000, lp, loop=True)
            return True
        return False

    made = 0
    with tempfile.TemporaryDirectory(prefix='skategm_loops_') as tmp:
        tmp = Path(tmp)
        for surface in range(14):
            for layer in (0, 2, 3, 'f0'):
                for k, speed in enumerate(SPEEDS):
                    if layer == 'f0':
                        a2 = render(tmp, 'GRINDS', 'Class_grind', grind_words(surface, 2, speed))
                        a1 = render(tmp, 'GRINDS', 'Class_grind', grind_words(surface, 1, speed))
                        mono = [x + y for x, y in zip(a2 or [], a1 or [])] if a2 and a1 else (a2 or a1)
                        name = f'{surface}_01_{k}.wav'
                    else:
                        mono = render(tmp, 'GRINDS', 'Class_grind', grind_words(surface, layer, speed))
                        name = f'{surface}_{layer}_{k}.wav'
                    made += save(out / 'grind' / name, mono)
            print('grind surface', surface)
        for surface in range(5):
            for k, speed in enumerate(SPEEDS):
                made += save(out / 'skid' / f'{surface}_{k}.wav', render(tmp, 'WHEEL_SKID_BANK', 'Class_wheels_skid',
                                                                       skid_words(surface, speed)))
        for surface in range(11):
            for k, speed in enumerate(SPEEDS):
                made += save(out / 'drag' / f'{surface}_{k}.wav', render(tmp, 'FOOT_DRAG', 'Class_foot_drag',
                                                                       drag_words(surface, speed)))
    print('Done:', made, 'loops in', out)


if __name__ == '__main__':
    main()
