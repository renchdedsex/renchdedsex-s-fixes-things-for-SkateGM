"""Skate 3's skate sounds for SkateGM (gm_sk8), from your own extracted game.

Writes a private add-on, garrysmod/addons/skategm_s3sounds/sound/skate3/:
  splice/<bank>/r<record>.wav     every record of a Splice (.bnk) bank, its layers
                                  mixed as retail plays them (the ids the native
                                  player posts: Skate_Collisions 1095 landing,
                                  1096 ollie, 1097..1099 pop, ... - see
                                  skate-audio/src/player/contacts.rs)
  splice/<bank>/index.txt         sound id -> records ("1097 r12 r13": a
                                  container picks one of them)
  abk/<bank>/<n>.wav              every sample of an AEMS (.abk) bank
  grains/<surface>/<band>.wav     each rolling surface's recording (slow to fast)
                                  cut into speed bands, each a seamless loop with
                                  a loop marker (Source loops it)
The files are EA's, from your copy of the game: keep them to yourself.

  python prepare_gmod_sounds.py --engine <skate-3-rust-engine> --game <Skate3-extracted>
      --gmod <GarrysMod> --vgmstream <vgmstream-cli.exe>
"""
import argparse
import importlib.util
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

SPLICE = ('Skate_Collisions.bnk', 'Skate_Metal.bnk', 'sk8_foley.bnk')
ABK = ('GRINDS.abk', 'board_scrapes.abk', 'WHEEL_SKID_BANK.abk', 'FOOT_DRAG.abk', 'fstep_skateshoe1_sm.abk',
       'Bodyslide.abk', 'Sk8_Air_Flip_Tricks.abk', 'Rolling_Rattles.abk', 'Seams_Bank.abk',
       'PatchBank_Rolling_Surfaces.abk', 'Brd_Squeaks.abk', 'Foley_Cloth.abk')
BANDS = 6
CROSSFADE = 0.08


def resample(rate, mono, target=44100):
    """Source plays only 44100 / 22050 / 11025 Hz; the game's sounds are 48000."""
    if rate == target or not mono:
        return mono
    n = max(1, int(len(mono) * target / rate))
    step = rate / target
    out = []
    for i in range(n):
        x = i * step
        k = int(x)
        f = x - k
        a = mono[min(k, len(mono) - 1)]
        b = mono[min(k + 1, len(mono) - 1)]
        out.append(a + (b - a) * f)
    return out


def write_wav(path, rate, mono, loop=False):
    """mono: list of floats (PCM16 scale). loop: add a smpl chunk looping the whole file."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if rate not in (44100, 22050, 11025):
        mono, rate = resample(rate, mono), 44100
    peak = max(1.0, max((abs(v) for v in mono), default=0) / 32767)
    data = struct.pack(f'<{len(mono)}h', *(int(v / peak) for v in mono))
    with wave.open(str(path), 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data)
    if loop and mono:
        # smpl chunk: one forward loop over every frame (and a cue point, which
        # Source also reads for looping)
        smpl = struct.pack('<9I', 0, 0, int(1e9 / rate), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack('<6I', 0, 0, 0, len(mono) - 1, 0, 0)
        cue = struct.pack('<I', 1) + struct.pack('<II4sIII', 0, 0, b'data', 0, 0, 0)
        raw = bytearray(path.read_bytes())
        raw += b'cue ' + struct.pack('<I', len(cue)) + cue
        raw += b'smpl' + struct.pack('<I', len(smpl)) + smpl
        struct.pack_into('<I', raw, 4, len(raw) - 8)
        path.write_bytes(bytes(raw))


def read_wav(path):
    with wave.open(str(path)) as w:
        rate, ch, n = w.getframerate(), w.getnchannels(), w.getnframes()
        pcm = struct.unpack(f'<{n * ch}h', w.readframes(n))
    return rate, [sum(pcm[i:i + ch]) / ch for i in range(0, len(pcm), ch)]


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--engine', type=Path, required=True)
    p.add_argument('--game', type=Path, required=True)
    p.add_argument('--gmod', type=Path, required=True)
    p.add_argument('--vgmstream', type=Path, required=True)
    a = p.parse_args()
    sys.path.insert(0, str(a.engine / 'tools'))
    from vendor.skate3_ui.big import BigArchive
    spec = importlib.util.spec_from_file_location('audio_formats', a.engine / 'tools/asset_pipeline/audio_formats.py')
    af = importlib.util.module_from_spec(spec)
    sys.modules['audio_formats'] = af
    spec.loader.exec_module(af)
    out = a.gmod / 'garrysmod/addons/skategm_s3sounds/sound/skate3'
    (out.parent.parent / 'addon.json').parent.mkdir(parents=True, exist_ok=True)
    (out.parent.parent / 'addon.json').write_text('{"title": "SkateGM - Skate 3 sounds (private)", "type": "effects", "tags": []}')
    big = BigArchive(a.game / 'data/audio/audiofiles.big')
    entry = {Path(e.path).name.lower(): e for e in big.entries}

    def decode(tmp, name, data, args=()):
        src = tmp / name
        src.write_bytes(data)
        subprocess.run([str(a.vgmstream), *args, '-o', str(tmp / (src.stem + '_?s.wav')), str(src)],
                       check=True, capture_output=True)

    with tempfile.TemporaryDirectory(prefix='skategm_snd_') as tmp:
        tmp = Path(tmp)
        # Splice banks: every record, its layers mixed
        for bank in SPLICE:
            data = big.read(entry[bank.lower()])
            streams, patches = af.splc_streams(data), af.splc_patches(data)
            decoded = {}

            def sample(n):
                if n not in decoded:
                    snr = tmp / f'{bank}_{n}.snr'
                    snr.write_bytes(af.standalone(data, streams[n]))
                    subprocess.run([str(a.vgmstream), '-o', str(snr.with_suffix('.wav')), str(snr)], check=True,
                                   capture_output=True)
                    decoded[n] = read_wav(snr.with_suffix('.wav'))
                return decoded[n]
            folder = out / 'splice' / Path(bank).stem
            for r, groups in enumerate(patches['records']):
                mix, rate = [], 48000
                for g in groups:
                    if not g['members']:
                        continue
                    n, gain = g['members'][0][0], g['members'][0][1]
                    rate, mono = sample(n)
                    if len(mix) < len(mono):
                        mix += [0.0] * (len(mono) - len(mix))
                    for i, v in enumerate(mono):
                        mix[i] += v * gain
                if mix:
                    write_wav(folder / f'r{r}.wav', rate, mix)
            lines = [f'{i} r{i}' for i in range(len(patches['records']))]
            base = len(patches['records'])
            for k, c in enumerate(patches['containers']):
                lines.append(f'{base + k} ' + ' '.join(f'r{m}' for m in c))
            (folder / 'index.txt').write_text('\n'.join(lines) + '\n')
            print(bank, len(patches['records']), 'records', len(patches['containers']), 'containers')
        # AEMS banks: every sample
        for bank in ABK:
            e = entry.get(bank.lower())
            if not e:
                print('missing', bank)
                continue
            work = tmp / Path(bank).stem
            work.mkdir()
            decode(work, bank, big.read(e), ('-S', '0'))
            folder = out / 'abk' / Path(bank).stem
            count = 0
            for wav in sorted(work.glob('*.wav'), key=lambda x: int(x.stem.rsplit('_', 1)[1])):
                rate, mono = read_wav(wav)
                write_wav(folder / f'{int(wav.stem.rsplit("_", 1)[1]) - 1}.wav', rate, mono)
                count += 1
            print(bank, count, 'samples')
        # rolling grains: speed bands, looped
        grains = BigArchive(a.game / 'data/audio/grains.big')
        for e in grains.entries:
            stem = Path(e.path).stem
            data = grains.read(e)
            g = af.grain(data)
            snr = tmp / f'{stem}.snr'
            snr.write_bytes(af.standalone(data, g.stream))
            subprocess.run([str(a.vgmstream), '-o', str(snr.with_suffix('.wav')), str(snr)], check=True,
                           capture_output=True)
            with wave.open(str(snr.with_suffix('.wav'))) as w:
                rate, ch, frames = w.getframerate(), w.getnchannels(), w.readframes(w.getnframes())
            if ch != 1:
                frames = af.downmix_pcm16(frames, ch)
            for i, pcm in enumerate(af.loop_bands(frames, BANDS, round(CROSSFADE * rate))):
                mono = list(struct.unpack(f'<{len(pcm) // 2}h', pcm))
                write_wav(out / 'grains' / stem / f'{i}.wav', rate, mono, loop=True)
            print('grain', stem)
    print('Done:', out)


if __name__ == '__main__':
    main()
