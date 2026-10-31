#!/usr/bin/env python3
"""Check repository text without retaining or echoing excluded identifiers."""
import argparse
import hashlib
import os
from pathlib import Path
import stat
import subprocess
import sys

# (normalized character count, initial code point, SHA-256). No plain-text labels.
RULES = (
    (9, 109, '266e0a1336f514f3bcea1d7669ff7af884cec8b98794ae29b4929e7fe95179e3'),
    (9, 109, 'a4c1663074a077e9a5051e6b3355244f72588be70c90afeec3e089bbbd187097'),
    (3, 29483, '54ee15910b64b21a73770912302af457d34e07adb36ae649ff2899b8787d8b8f'),
)


def restricted(text, rules=RULES):
    text = text.casefold()
    for length, first, digest in rules:
        cursor = text.find(chr(first))
        while cursor >= 0:
            candidate = text[cursor:cursor + length]
            if len(candidate) == length and hashlib.sha256(candidate.encode('utf-8', 'surrogatepass')).hexdigest() == digest:
                return True
            cursor = text.find(chr(first), cursor + 1)
    return False


def text_hit(data, rules=RULES):
    return b'\0' not in data and restricted(data.decode('utf-8', 'replace'), rules)


def git(root, *args):
    result = subprocess.run(['git', '-C', str(root), *args], capture_output=True, check=False)
    if result.returncode:
        raise RuntimeError('Repository policy check could not read Git data.')
    return result.stdout


def safe_path(name):
    return 'path-sha256:' + hashlib.sha256(name.encode('utf-8', 'surrogatepass')).hexdigest()[:16] if restricted(name) else name


def check_message(path, rules=RULES):
    text = Path(path).read_bytes().decode('utf-8', 'replace')
    return ['pending commit message'] if restricted(text, rules) else []


def check_staged(root, rules=RULES):
    issues = []
    changed = git(root, 'diff', '--cached', '--name-only', '--diff-filter=ACMR', '-z')
    for path in changed.split(b'\0'):
        if not path:
            continue
        name = os.fsdecode(path)
        if restricted(name, rules) or text_hit(git(root, 'show', ':' + name), rules):
            issues.append('staged ' + safe_path(name))
    return issues


def check_worktree(root, rules=RULES):
    issues = []
    names = set(git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0'))
    for path in names:
        if not path:
            continue
        name = os.fsdecode(path)
        file = root / name
        try:
            mode = file.lstat().st_mode
        except FileNotFoundError:
            continue  # Deletions contain no working-tree text.
        if stat.S_ISLNK(mode):
            body = os.fsencode(os.readlink(file))
        elif stat.S_ISREG(mode):
            body = file.read_bytes()
        else:
            continue
        if restricted(name, rules) or text_hit(body, rules):
            issues.append('working file ' + safe_path(name))
    return issues


def check_refs(root, rules=RULES):
    refs = git(root, 'for-each-ref', '--format=%(refname)').decode().splitlines()
    return ['ref-sha256:' + hashlib.sha256(ref.encode()).hexdigest()[:16]
            for ref in refs if restricted(ref, rules)]


def check_history(root, rules=RULES):
    if git(root, 'rev-parse', '--is-shallow-repository').strip() != b'false':
        raise RuntimeError('Full history is required; checkout with fetch-depth: 0.')
    issues = check_refs(root, rules)
    objects = git(root, 'rev-list', '--objects', '--all', '--no-object-names').decode().splitlines()
    process = subprocess.Popen(['git', '-C', str(root), 'cat-file', '--batch'],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    try:
        for oid in objects:
            process.stdin.write((oid + '\n').encode())
            process.stdin.flush()
            header = process.stdout.readline().decode().split()
            if len(header) != 3:
                raise RuntimeError('Repository object could not be inspected.')
            _, kind, size = header
            body = process.stdout.read(int(size))
            if process.stdout.read(1) != b'\n' or len(body) != int(size):
                raise RuntimeError('Repository object was truncated.')
            metadata_hit = kind in ('commit', 'tag') and restricted(body.decode('utf-8', 'replace'), rules)
            if metadata_hit or kind == 'blob' and text_hit(body, rules):
                issues.append(kind + ':' + oid)
    finally:
        process.stdin.close()
        process.stdout.close()
        if process.wait(timeout=10):
            raise RuntimeError('Repository object scan failed.')
    # One blob can have multiple names; rev-list's single name is not sufficient.
    trees = set(git(root, 'log', '--all', '--format=%T').decode().splitlines())
    paths = set()
    for tree in trees:
        paths.update(git(root, 'ls-tree', '-r', '--name-only', '-z', tree).split(b'\0'))
    for path in paths:
        if path and restricted(os.fsdecode(path), rules):
            issues.append('historical-path-sha256:' + hashlib.sha256(path).hexdigest()[:16])
    return issues


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path.cwd())
    parser.add_argument('--message', type=Path)
    parser.add_argument('--staged', action='store_true')
    parser.add_argument('--worktree', action='store_true')
    parser.add_argument('--history', action='store_true')
    args = parser.parse_args()
    root = args.root.resolve()
    try:
        issues = []
        if args.message:
            issues += check_message(args.message)
        if args.staged:
            issues += check_staged(root)
        if args.worktree or not (args.message or args.staged or args.history):
            issues += check_worktree(root)
        if args.history:
            issues += check_history(root)
        else:
            issues += check_refs(root)
    except (OSError, RuntimeError, subprocess.SubprocessError):
        print('Repository text policy could not complete; no input text was logged.', file=sys.stderr)
        return 2
    if issues:
        print('Repository text policy failed at ' + str(len(set(issues))) + ' location(s):', file=sys.stderr)
        for issue in sorted(set(issues)):
            print('  ' + issue, file=sys.stderr)
        return 1
    print('ok: repository text policy')
    return 0


if __name__ == '__main__':
    sys.exit(main())
