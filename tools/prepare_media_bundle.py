"""Prepare pinned macOS arm64 LOCAL TEST components. No downloads.

The combined extractor is GPLv3+, not just Unlicense. Public redistribution
and store approval are not granted by this local-test packaging tool.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PINS = {
    'extractor': '20d98fa608998eff87d1d35a6e9fb65e4b874639a6cc89addc19da3becde3ef1',
    'runtime': '7c5b6cb31520628d21b31a03dc213d7baa597a7c42e9796b6009ff6437e6d60c',
}
LICENSES = ['LICENSE', 'THIRD_PARTY_LICENSES.txt', 'GPL-3.0.txt', 'DENO-LICENSE.md']


def digest(path):
    with path.open('rb') as stream:
        value = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(chunk)
        return value.hexdigest()


def sign(path, role, inherit=False):
    command = ['codesign', '--force', '--sign', '-', '--identifier', 'io.timbrebox.media.' + role]
    if inherit:
        command += ['--entitlements', str(ROOT / 'scripts/media/helper.entitlements')]
    subprocess.run(command + [str(path)], check=True, capture_output=True)


def prepare(extractor, runtime, licenses, output):
    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Only the reviewed macOS arm64 local-test profile is supported.')
    if output.exists():
        raise ValueError('Output exists; choose a new private build directory.')
    for name, file in [('extractor', extractor), ('runtime', runtime)]:
        if not file.is_file() or digest(file) != PINS[name]:
            raise ValueError('Reviewed input digest mismatch: ' + name)
    for name in LICENSES:
        if not (licenses / name).is_file() or not (licenses / name).stat().st_size:
            raise ValueError('Required original notice missing: ' + name)
    output.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix='.media-prepare-', dir=output.parent))
    try:
        helper = stage / 'TimbreBoxMedia.app'
        contents = helper / 'Contents'
        binaries = contents / 'MacOS'
        binaries.mkdir(parents=True)
        resources = stage / 'Resources'
        payload = resources / 'Extractor'
        payload.mkdir(parents=True)
        with zipfile.ZipFile(extractor) as archive:
            if sum(i.file_size for i in archive.infolist()) > 256 * 1024 * 1024:
                raise ValueError('Component exceeds the reviewed extraction budget.')
            for entry in archive.infolist():
                path = Path(entry.filename)
                if path.is_absolute() or '..' in path.parts or (entry.external_attr >> 16) & 0o170000 == 0o120000:
                    raise ValueError('Unsafe component archive member.')
            archive.extractall(payload)
        (payload / 'yt-dlp_macos').rename(payload / 'yt-dlp')
        (resources / 'Runtime').mkdir()
        shutil.copyfile(runtime, resources / 'Runtime/deno')
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleExecutable': 'media-supervisor',
            'CFBundleIdentifier': 'io.timbrebox.media.supervisor',
            'CFBundleName': 'TimbreBox Media', 'CFBundlePackageType': 'APPL',
            'CFBundleVersion': '1', 'LSBackgroundOnly': True,
        }))
        build_env = dict(os.environ)
        build_env.pop('SDKROOT', None)
        subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-std=c11', '-Os',
                        '-mmacosx-version-min=12.0', '-Wall', '-Wextra', '-Werror',
                        str(ROOT / 'tools/media_supervisor.c'), '-o', str(binaries / 'media-supervisor')],
                       check=True, env=build_env)
        # Keep original library signatures and all package data/notices intact.
        # Only process entrypoints need sandbox inheritance. Directory mode does
        # not unpack executable code into writable temp or need SysV semaphores.
        (payload / 'yt-dlp').chmod(0o755)
        sign(payload / 'yt-dlp', 'extractor', inherit=True)
        for role, file in [('runtime', resources / 'Runtime/deno'), ('supervisor', binaries / 'media-supervisor')]:
            file.chmod(0o755)
            sign(file, role, inherit=True)
        subprocess.run(['codesign', '--force', '--sign', '-', '--entitlements',
                        str(ROOT / 'scripts/media/helper.entitlements'), str(helper)],
                       check=True, capture_output=True)
        subprocess.run(['codesign', '--verify', '--strict', str(helper)], check=True, capture_output=True)
        notice = resources / 'Licenses'
        notice.mkdir()
        for name in LICENSES:
            shutil.copyfile(licenses / name, notice / name)
        files = {'supervisor': binaries / 'media-supervisor',
                 'extractor': payload / 'yt-dlp', 'runtime': resources / 'Runtime/deno'}
        manifest = {
            'schema': 1, 'distribution': 'local-test-only',
            'extractorVersion': '2026.10.26', 'runtimeVersion': '2.6.9',
            **{role: {'name': file.name, 'sha256': digest(file)} for role, file in files.items()},
            'payload': {str(file.relative_to(payload)): digest(file)
                        for file in sorted(payload.rglob('*')) if file.is_file()},
            'licenses': {name: digest(notice / name) for name in LICENSES},
        }
        (resources / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
        stage.rename(output)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return digest(output / 'Resources/manifest.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ['extractor', 'runtime', 'licenses', 'output']:
        parser.add_argument('--' + name, required=True, type=Path)
    args = parser.parse_args()
    value = prepare(args.extractor, args.runtime, args.licenses, args.output)
    print(json.dumps({'local_test_only': True, 'bundleManifestSha256': value}))


if __name__ == '__main__':
    main()
