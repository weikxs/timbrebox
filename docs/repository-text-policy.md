# Repository text policy

Repository text, commit messages and reference names must pass the same case-insensitive policy.
The checker stores only fingerprints, never the excluded labels in plain text. Diagnostics do not echo
matched source text; restricted paths and ref names are represented by hashes.

## Local checks

```sh
make text-policy
make hooks
```

`make text-policy` checks tracked/untracked non-ignored working files, all reachable history and reference
names, and runs the offline policy tests. The commit-message hook checks the proposed message and staged
files. The pre-push hook checks the working tree and full local history. Hooks do not make commits or push.

The same checks run in CI with a full-history checkout. A shallow history is an error, not a successful
partial scan. CI changes only take effect after they are committed and published.

## Scope

- UTF-8 text, commit/tag metadata, Git notes stored in reachable objects, and current/historical paths.
- Every local ref, including remote-tracking refs and tags, not only the current branch.
- Symlinks are inspected as link text; the checker never follows them into private external files.
- Ignored local data, binary media/OCR, provider-side caches, other people's forks and external clones are
  outside this textual repository check. Review private local specifications separately when needed.

The checker only reports; it never deletes attribution, changes authorship, rewrites history or edits code.
Any required license or attribution must remain valid. Review a match before deciding whether code needs
independent implementation or removal.

## After a coordinated history rewrite

Do not fetch or merge stale remote history back into a cleaned repository. Coordinate lease-checked remote
updates first, then verify a new full clone. Other existing clones should be replaced or explicitly migrated.
Keep private rollback bundles outside the repository until verification is complete; never publish them.
Signatures on changed commits cannot be carried over as valid signatures. Preserve unchanged signatures;
any new signing must be performed by the authorized signer.
