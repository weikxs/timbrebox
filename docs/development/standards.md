# Development Standards

These rules apply to every change, by anyone, including the maintainers. **MUST** rules are enforced by tooling
or review; **SHOULD** rules need a reason in the pull request when broken. Where a tool enforces a rule, the
rule says which; "review" means a maintainer checks it. The workflow and boundaries for people and agents in
[AGENTS.md](../../AGENTS.md) apply as well.

## 1. Standards we follow

| Area | Standard |
|---|---|
| Versioning | [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) |
| Commit messages | [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) |
| Changelog | [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) |
| Dart style | [Effective Dart](https://dart.dev/effective-dart), `dart format` of Flutter 3.44 (Dart 3.12), the analyzer with [`flutter_lints`](https://pub.dev/packages/flutter_lints) / [`lints`](https://pub.dev/packages/lints), no issues |
| Shell style | POSIX `sh` unless Bash is needed, clean under [ShellCheck](https://www.shellcheck.net) |
| Workflows | Clean under [actionlint](https://github.com/rhysd/actionlint) |
| User interface | [WCAG 2.2](https://www.w3.org/TR/WCAG22/) level AA as the goal; the visual rules of [docs/DESIGN.md](../DESIGN.md) |
| CLI behavior | [Command Line Interface Guidelines](https://clig.dev/) |
| Community | [Contributor Covenant 2.1](https://www.contributor-covenant.org/version/2/1/code_of_conduct/) |
| Security reporting | Private GitHub Security Advisories ([SECURITY.md](../../SECURITY.md)) |
| License | [PolyForm Noncommercial 1.0.0](../../LICENSE) |

## 2. Contribution process

- **Issue first.** Every change starts from an issue. Bugs and documentation fixes are welcome straight away.
  New features, new sources, changes to the plugin format, the control API or what the interface shows need a
  maintainer's go-ahead on the issue **before** code is written; pull requests for features without one may be
  closed.
- **Bug reports** answer five questions: the TimbreBox version or commit, the system and CPU, what you did, what
  you expected and what happened — with placeholders for personal paths, accounts and private links (§4).
- **One pull request, one purpose.** Do not mix a fix, a refactor and a feature; split them.
- **Review:** every change reaches `main` through a pull request with the `check` job green (§6). Contributors'
  pull requests also need an approval from a code owner (`.github/CODEOWNERS`). Maintainers follow the same rule;
  a documentation-only pull request still runs CI's `check` job, which runs the privacy check, sees that nothing
  testable changed and passes in seconds. Nobody bypasses the checks.
- **Response times** are best effort; security reports follow [SECURITY.md](../../SECURITY.md).

## 3. AI-assisted contributions (MUST)

AI tools may help write code, tests and docs. The person who opens the pull request is its author and is
responsible for every line.

- **Understand it.** You must be able to explain the change, its edge cases and side effects in your own words.
- **Verify it.** Run the tests and check the behavior yourself, on the platforms it touches. AI output that "looks
  right" is not evidence.
- **No autonomous agents.** Pull requests and issues come from a person's own account, opened and answered by that
  person. Pull requests that look generated and unattended are closed.
- **Say so** in the pull request description when AI wrote a substantial part of the change, and what it did.
- **Security reports found with AI** must be reproduced by you before you report them, and say that AI was used.
- **Commits carry no tool or bot attribution** (no `Co-Authored-By` for tools, no "generated with" lines): the
  human author is the author. Enforced by the `commit-msg` hook.
- Privacy (§4) applies to prompts too: never paste real accounts, cookies, tokens or private paths into an AI
  tool's prompt for this project.

## 4. Privacy and test data (MUST)

Enforced by `make privacy` (pre-commit hook and CI, on every pull request) and review.

- **Never commit real account names, emails, organization names, cookies, tokens, keys, private plugin or
  subscription links, hostnames or local paths** — not in code, tests, fixtures, docs, screenshots, release notes,
  commit messages or issues.
- Use only demo data:

  | Kind | Demo values |
  |---|---|
  | Hosts | `example.com`, `example.org`, `*.example`, `*.test` ([RFC 2606](https://www.rfc-editor.org/rfc/rfc2606)); `127.0.0.1` for loopback |
  | Home paths | The demo user `me`: `/Users/me/…`, `/home/me/…`, `C:\Users\me\…` — the only user name `make privacy` accepts in a home path |
  | Tokens and keys | Generated at random inside the test |
  | Tracks | Titles and artists made up for the test, or public-domain recordings |

- **Tests never touch real user data.** Tests keep their files in temporary folders they create and remove; they
  never read or write the app's real support folder, settings, library or downloads.
- **Screenshots** in `docs/screenshots/` show only public sources' results and the app's own settings, never a
  personal path, account or token.
- Each contributor may add their own real identifiers, one regular expression per line, to the git-ignored
  `.privacy-denylist`.

## 5. Security (MUST)

- **No user credentials.** TimbreBox never asks for, collects or stores source accounts, browser or imported
  cookies, API keys, tokens or device identifiers. An anonymous temporary cookie a source needs lives in memory
  only and is cleared on exit; it is never written to disk, logs or a database.
- **Plugins:** a plugin's script runs in the sandboxed JavaScript engine with HTTP as its only capability; every
  request, redirect hop and stream it causes passes the egress checks, and every plugin stream goes through the
  loopback proxy. Mobile builds never download or run plugin code. No dynamic `eval` of downloaded code outside
  the sandbox.
- **Loopback services** (the control API and the stream proxy) listen on `127.0.0.1` only, check the `Host`
  header, refuse web pages, and use random per-run tokens; the control token file is readable by the user only.
- **Files:** settings, the session, the library and plugin files are written atomically (temporary file, then
  rename); downloads stay inside the download folder, whose index stores file names only.
- Never write tokens, cookies or private links to logs or error messages; user-facing errors name no local path.
  There is no telemetry.
- No DRM circumvention and no paid-content scraping.

## 6. Supply chain

| Rule | Level | Enforced by |
|---|---|---|
| `main` is protected: changes arrive only through pull requests, squash-merged, with the `check` job green; no force-push or deletion; linear history; nobody bypasses the rules, maintainers included (§2) | MUST | repository ruleset |
| Release tags `v*` are never moved or deleted once a release is published | MUST | repository ruleset |
| Workflows declare least-privilege `permissions` (read-only by default; `contents: write` only for the release jobs) | MUST | review |
| Third-party actions are pinned to a full commit SHA, with the version in a comment; Flutter is installed from its git tag, not by a third-party action | MUST | review |
| Dependencies are updated by Dependabot: one grouped pull request per ecosystem (pub, GitHub Actions) per month; major versions are upgraded on purpose, with their own tests | MUST | `.github/dependabot.yml` |
| A new dependency needs a reason in the pull request: maintenance, size, license compatible with the project's | MUST | review |
| `pubspec.lock` files are committed | MUST | review |
| Release packages are built in CI only, never on a developer's machine, and published with SHA-256 `checksums.txt`; the install script and Homebrew verify them | MUST | release workflow, `install.sh` |

## 7. Code

- **Layout:** the pure-Dart domain lives in `packages/timbrebox_core`, the online sources in
  `packages/timbrebox_sources`, the playback backend in `packages/timbrebox_playback`, the command line and MCP
  server in `packages/timbrebox_cli`, the Flutter app in `apps/timbrebox_app`. Inside the app, directories follow
  features and sources, as described in [AGENTS.md](../../AGENTS.md).
- **Size:** functions under 50 lines; a file stays under 800 lines — split it as it grows; nesting at most 4
  levels, prefer early returns.
- **Analysis and formatting:** `dart format` and the analyzer with no issues (`make check`).
- **Immutability:** state the interface renders is immutable; prefer returning new values over mutating inputs.
- **No fake data:** every value comes from a real source, with honest loading, error and empty states; no mock or
  placeholder data outside tests.
- **No magic values:** name constants for timeouts, limits, cache sizes and ports.
- **Texts:** every interface text exists in English and Simplified Chinese, in the same change.
- **Shell scripts** (`install.sh`, `scripts/`, `tools/`): `set -eu` (Bash: `set -euo pipefail`), quote every
  expansion, ShellCheck clean (run it in a container before pushing). `install.sh` verifies the checksum before
  installing, uses `sudo` only to install a system package and says so first, and changes nothing but the app,
  its menu entry and one marked `PATH` line.
- **Workflows** pass actionlint (run it in a container before pushing).

## 8. Tests (MUST)

- **Test first:** write a failing test, make it pass, then refactor.
- **Coverage:** 80% of lines is the goal for new code; parsers are tested against recorded fixtures.
- **Style:** descriptive test names; Arrange–Act–Assert.
- **Isolation:** no network outside loopback in the default test run; network integration tests are tagged
  separately. Tests wait for conditions, never for a fixed time that a slow machine may miss.
- **Never install anything on the developer's machine** to run a test. Tests that need another system run in
  containers or in CI: at most one container at a time, with a CPU and memory limit.
- **Platforms:** CI runs the analysis, formatting and tests on Linux for every pull request. The full workflow,
  started by hand before a release, runs the analysis and tests on macOS and Windows and builds every desktop
  release package, Android and iOS. The release workflow installs and starts each package on a fresh macOS, Linux
  and Windows machine before publishing it.

## 9. Git workflow

- **Branching:** GitHub Flow. `main` is always releasable; work happens on short-lived branches (`feat/…`,
  `fix/…`, `perf/…`, `docs/…`, `refactor/…`, `test/…`, `ci/…`, `chore/…`, `build/…`).
- **Commits:** Conventional Commits, subject at most 72 characters, imperative, enforced by the `commit-msg` hook
  (`make hooks`). One logical change per commit; the body says *why*. Reference issues in the body (`Fixes #123`).
- **Squash** fix-up commits ("address review", "fix typo") before merging. Pull requests are squash-merged with a
  Conventional Commit title.
- Commits are authored by the contributor's own account, with no tool or bot attribution trailers.
- **Never** force-push to `main` or rewrite published history; a tag whose release is published is never moved
  or deleted.

## 10. Versioning, changelog and releases

- SemVer. Before 1.0, minor versions may contain breaking changes; they are called out in the changelog and in the
  release notes' "Before you upgrade".
- Every user-visible change adds a line under **Unreleased** in `CHANGELOG.md` (Added / Changed / Deprecated /
  Removed / Fixed / Security), in the user's words. Internal refactors and dependency bumps without user impact
  get no entry; a bump that fixes a vulnerability users were exposed to does.
- **Release notes** are product communication, one file per release in `.github/release-notes/vX.Y.Z.md`, in the
  layout of `.github/release-notes/TEMPLATE.md`. Draft with
  `scripts/release-notes.sh vX.Y.Z > .github/release-notes/vX.Y.Z.md`, then write the TODO parts.
  `CHANGELOG.md` stays the complete engineering record.
- **Release:** move the Unreleased entries to a new version section with its date, set the version in
  `apps/timbrebox_app/pubspec.yaml` (`X.Y.Z+<build>`), write the release notes, merge to `main`, then tag `vX.Y.Z`
  on `main` and push the tag (`vX.Y.Z-rc.N` for a pre-release, with its own notes file). The release workflow
  stops when the version differs from the tag or the notes are missing or still have TODOs; then it runs every
  check, builds the universal macOS disk image, the Linux x86_64 `.deb` and `.tar.gz` and the Windows x64 `.zip`,
  installs and starts each on a fresh machine (with `install.sh` on macOS and Linux), publishes them with
  `checksums.txt` and the notes, and updates the Homebrew cask when the `HOMEBREW_TAP_SSH_KEY` secret is set (a
  pre-release only on the tap's `rc/timbrebox` branch).
- **Not signed:** the macOS app is not signed or notarized by Apple and will not be; the Windows app is not signed.
  The README, the release notes and [SECURITY.md](../../SECURITY.md#release-packages-and-macos) say how to open them.
- **Android and iOS** are not released as packages: an Android package needs a signing key kept for every future
  release, and iOS needs Apple signing. Both are built from source.
- **After a release,** verify the release page, a download against `checksums.txt`, the install script and, when
  the cask was updated, `brew install --cask weikxs/tap/timbrebox`.

## 11. Documentation

- Public docs are in English, each with a Simplified Chinese `*.zh-CN.md` sibling updated in the same pull request.
- Every command or setting change updates the README and the built-in help text.
- Statements in the docs must be true of the code: a released platform is built and tested in CI, a promise in
  "Privacy and security" is enforced by a test or a rule above.
- Product requirements, designs and planning are internal and are not published (`docs/prd/` and `docs/internal/`
  are git-ignored).

## 12. Definition of done

A change is done when:

- [ ] it starts from an issue, and a feature had a maintainer's go-ahead;
- [ ] tests were written first and pass;
- [ ] `make check` passes (privacy, analysis, formatting, tests); scripts are ShellCheck clean and workflows
  actionlint clean;
- [ ] no real identities, local paths, cookies or tokens (`make privacy`);
- [ ] errors are handled and messages are actionable, in both languages;
- [ ] `CHANGELOG.md`, README (both languages) and help text are updated where relevant;
- [ ] the author understands and has verified every line, including AI-assisted parts;
- [ ] the pull request has the `check` job green and is squash-merged with a Conventional Commit title.
