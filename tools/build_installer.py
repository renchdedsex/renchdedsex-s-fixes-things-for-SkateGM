"""Builds release/SkateGM-Setup-<version>.exe (version from VERSION): the installer window, the converter, the
add-on and the engine module in one file. Nothing from the game is bundled.

    python tools/build_installer.py

Needs Rust (for the converter's refpack.dll) and Python 3; makes its own
build environment in .build/venv with pinned packages.
"""
from pathlib import Path
import shutil, subprocess, sys, venv

ROOT = Path(__file__).resolve().parent.parent
BUILD = ROOT / '.build'
VENV = BUILD / 'venv'
PY = VENV / ('Scripts/python.exe' if sys.platform == 'win32' else 'bin/python')
PACKAGES = ['numpy==2.5.3', 'pillow==12.3.0', 'pyinstaller']
DLL = ROOT / 'gm_skategm' / 'prebuilt' / 'gmcl_skategm_win64.dll'
SEP = ';' if sys.platform == 'win32' else ':'
NAME = 'SkateGM-Setup-' + (ROOT / 'VERSION').read_text(encoding='utf-8').strip()


def run(*args):
    print('>', ' '.join(map(str, args)), flush=True)
    subprocess.run([str(a) for a in args], check=True)


def main():
    if not DLL.is_file():
        raise SystemExit(f'build the module first: {DLL} is missing')
    if not PY.is_file():
        venv.create(VENV, with_pip=True)
    run(PY, '-m', 'pip', 'install', '--quiet', '--disable-pip-version-check', *PACKAGES)
    work = BUILD / 'installer'
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir(parents=True)
    refpack = work / 'refpack.dll'
    run('rustc', '--edition', '2024', '--crate-type', 'cdylib', '-C', 'opt-level=3', '-C', 'panic=abort',
        '-C', 'target-feature=+crt-static', ROOT / 'exporter' / 'tools' / 'asset_pipeline' / 'refpack_native.rs', '-o', refpack)
    licenses = work / 'licenses'
    licenses.mkdir()
    for src, name in [('engine/LICENSE', 'engine-LICENSE.txt'), ('engine/NOTICE-mashup', 'engine-NOTICE.txt'),
                      ('LICENSE-THIRD-PARTY.md', 'README.md'), ('exporter/tools/vendor/utt/LICENSE', 'UTT.txt'),
                      ('exporter/tools/vendor/university/LICENSE-PROJECT.md', 'CustomEngineLayer.txt'),
                      ('exporter/tools/vendor/skate3_ui/LICENSE', 'skate3_ui.txt')]:
        shutil.copy2(ROOT / src, licenses / name)
    out = ROOT / 'release'
    run(PY, '-m', 'PyInstaller', '--noconfirm', '--clean', '--onefile', '--windowed', '--name', NAME,
        '--paths', ROOT / 'exporter',
        '--hidden-import', 'numpy', '--hidden-import', 'PIL.Image', '--hidden-import', 'convert',
        '--add-binary', f'{refpack}{SEP}tools/asset_pipeline',
        '--add-data', f'{ROOT / "exporter" / "tools"}{SEP}tools',
        '--add-data', f'{ROOT / "addon" / "skategm"}{SEP}payload/addon',
        '--add-binary', f'{DLL}{SEP}payload',
        '--add-data', f'{licenses}{SEP}licenses',
        '--exclude-module', 'bpy', '--exclude-module', 'mathutils',
        '--copy-metadata', 'numpy', '--copy-metadata', 'Pillow',
        '--distpath', out, '--workpath', work / 'build', '--specpath', work,
        ROOT / 'installer' / 'setup_skategm.py')
    print('built', out / (NAME + '.exe'))


if __name__ == '__main__':
    main()
