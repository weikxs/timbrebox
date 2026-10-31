"""OS-level cancellation test; synthetic child fixture, not platform evidence."""
import os
from pathlib import Path
import platform
import selectors
import signal
import subprocess
import tempfile
import time
import unittest


@unittest.skipUnless(platform.system() == 'Darwin', 'macOS native supervisor')
class SupervisorTest(unittest.TestCase):
    def test_cancel_reaps_extractor_and_terminates_its_worker_group(self):
        root = Path(__file__).resolve().parents[1]
        with tempfile.TemporaryDirectory(prefix='media-supervisor-test-') as temporary:
            contents = Path(temporary) / 'Contents'
            binaries = contents / 'Helpers/TimbreBoxMedia.app/Contents/MacOS'
            binaries.mkdir(parents=True)
            extractor = contents / 'Resources/TimbreBoxMedia/Extractor/yt-dlp'
            extractor.parent.mkdir(parents=True)
            extractor.write_text('#!/bin/sh\n/bin/sleep 60 &\nprintf "%s\\n" "$!"\nwait\n')
            extractor.chmod(0o700)
            env = dict(os.environ)
            env.pop('SDKROOT', None)
            executable = binaries / 'media-supervisor'
            subprocess.run(['xcrun', '--sdk', 'macosx', 'clang', '-std=c11', '-Os',
                            '-mmacosx-version-min=12.0', str(root / 'tools/media_supervisor.c'),
                            '-o', str(executable)], check=True, env=env, capture_output=True)
            process = subprocess.Popen([str(executable)], stdout=subprocess.PIPE,
                                       stderr=subprocess.DEVNULL, start_new_session=True)
            child = None
            group = None
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(process.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=3), 'Fixture child did not start')
                child = int(process.stdout.readline())
                group = os.getpgid(child)
                self.assertNotEqual(group, os.getpgrp())
                process.send_signal(signal.SIGTERM)
                self.assertEqual(process.wait(timeout=3), 125)
                for _ in range(30):
                    state = subprocess.run(['ps', '-p', str(child), '-o', 'stat='], capture_output=True, text=True)
                    if not state.stdout.strip() or state.stdout.strip().startswith('Z'):
                        break
                    time.sleep(0.05)
                else:
                    self.fail('A cancelled extractor left an active worker behind')
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=3)
                process.stdout.close()
                if group is not None:
                    try:
                        os.killpg(group, signal.SIGKILL)
                    except ProcessLookupError:
                        pass


if __name__ == '__main__':
    unittest.main()
