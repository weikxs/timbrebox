"""Offline policy tests use synthetic markers, never the production labels."""
import hashlib
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from check_repository_text import (
    check_history, check_message, check_refs, check_staged, check_worktree,
    restricted, text_hit,
)

TOKEN = 'excluded-demo-token'
RULES = ((len(TOKEN), ord(TOKEN[0]), hashlib.sha256(TOKEN.encode()).hexdigest()),)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='repository-policy-')
        self.root = Path(self.directory.name) / 'repo'
        self.root.mkdir()
        self.git('init', '-q', '-b', 'main', '--template=')
        self.git('config', 'user.name', 'Demo')
        self.git('config', 'user.email', 'demo@example.org')
        self.git('config', 'core.hooksPath', '.git/no-hooks')
        self.git('-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'chore: initialize fixture')

    def tearDown(self):
        self.directory.cleanup()

    def git(self, *args):
        return subprocess.run(['git', '-C', str(self.root), *args], check=True,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE).stdout

    def commit(self, message):
        self.git('add', '-A')
        self.git('-c', 'commit.gpgsign=false', 'commit', '-qm', message)

    def test_substrings_and_casefold(self):
        self.assertTrue(restricted('prefix_' + TOKEN.upper() + '_suffix', RULES))
        self.assertFalse(restricted('ordinary source text', RULES))
        self.assertFalse(restricted('ordinary \ud800 text', RULES))

    def test_unicode_rules(self):
        token = '\u6d4b\u8bd5\u8bcd'
        rules = ((len(token), ord(token[0]), hashlib.sha256(token.encode()).hexdigest()),)
        self.assertTrue(restricted('before' + token + 'after', rules))

    def test_binary_text_is_out_of_scope(self):
        self.assertFalse(text_hit(b'\0' + TOKEN.encode(), RULES))
        self.assertTrue(text_hit(TOKEN.encode(), RULES))

    def test_commit_message(self):
        path = Path(self.directory.name) / 'message.txt'
        path.write_text('fix: ' + TOKEN.upper())
        self.assertEqual(check_message(path, RULES), ['pending commit message'])
        path.write_bytes(b'\0' + TOKEN.encode())
        self.assertEqual(check_message(path, RULES), ['pending commit message'])

    def test_staged_blob_and_filename(self):
        (self.root / 'demo.md').write_text(TOKEN.upper())
        self.git('add', 'demo.md')
        self.assertTrue(check_staged(self.root, RULES))
        (self.root / 'demo.md').write_text('clean')
        self.git('add', 'demo.md')
        self.assertFalse(check_staged(self.root, RULES))
        (self.root / (TOKEN + '.md')).write_text('clean')
        self.git('add', '-A')
        self.assertTrue(check_staged(self.root, RULES))

    def test_untracked_working_files_and_deletions(self):
        path = self.root / 'demo.md'
        path.write_text(TOKEN)
        self.assertTrue(check_worktree(self.root, RULES))
        path.write_text('clean')
        self.commit('docs: add fixture')
        path.unlink()
        self.assertFalse(check_worktree(self.root, RULES))

    def test_ignored_private_files_are_not_read(self):
        (self.root / '.gitignore').write_text('private.txt\n')
        (self.root / 'private.txt').write_text(TOKEN)
        self.assertFalse(check_worktree(self.root, RULES))

    @unittest.skipIf(os.name == 'nt', 'Symlink creation requires Windows privileges')
    def test_symlink_does_not_read_external_content(self):
        external = Path(self.directory.name) / 'outside.md'
        external.write_text(TOKEN)
        (self.root / 'link.md').symlink_to('../outside.md')
        self.assertFalse(check_worktree(self.root, RULES))

    def test_deleted_historical_blob_and_path_are_still_detected(self):
        path = self.root / (TOKEN + '.md')
        path.write_text(TOKEN)
        self.commit('docs: add historical fixture')
        path.unlink()
        self.commit('docs: remove fixture')
        self.assertFalse(check_worktree(self.root, RULES))
        issues = check_history(self.root, RULES)
        self.assertTrue(any(issue.startswith('blob:') for issue in issues))
        self.assertTrue(any(issue.startswith('historical-path-sha256:') for issue in issues))

    def test_historical_message_and_ref(self):
        self.git('-c', 'commit.gpgsign=false', 'commit', '--allow-empty', '-qm', 'chore: ' + TOKEN)
        self.git('branch', 'topic/' + TOKEN)
        self.assertTrue(check_refs(self.root, RULES))
        self.assertTrue(any(issue.startswith('commit:') for issue in check_history(self.root, RULES)))

    def test_shallow_history_is_rejected(self):
        (self.root / '.git/shallow').write_bytes(self.git('rev-parse', 'HEAD'))
        with self.assertRaises(RuntimeError):
            check_history(self.root, RULES)


if __name__ == '__main__':
    unittest.main()
