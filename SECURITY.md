# Security Policy

TimbreBox runs third-party source plugins, serves a local control API and relays audio streams on the
loopback interface, so we treat security reports as the highest priority.

## Supported versions

Until 1.0, only the latest commit on `main` and the latest release receive security fixes.

## Reporting a vulnerability

**Do not open a public issue.** Report privately through
[GitHub Security Advisories](https://github.com/weikxs/timbrebox/security/advisories/new).

Please include:

- the platform and operating system, and the TimbreBox version or commit;
- steps to reproduce, with personal paths, accounts and private links replaced by placeholders;
- the impact you expect (for example, a plugin reading files outside its folder, or another program
  using the control API without its token).

## What to expect

| Step | Target |
|---|---|
| Acknowledge the report | within 3 days |
| Initial assessment | within 7 days |
| Fix for confirmed critical issues | as soon as possible, normally within 30 days |

We credit reporters in the release notes unless they prefer to stay anonymous.

## Release packages and macOS

Every release publishes `checksums.txt` with the SHA-256 of each package; the install script refuses a package that
does not match it. Packages are built by GitHub Actions from this repository's source, never on a developer's
machine.

The macOS app is not signed with an Apple Developer ID or notarized by Apple, and there are no plans to sign it.
`checksums.txt` lets you confirm a download is the released file. The Homebrew cask and the install script check the
checksum, then remove the quarantine attribute from the installed `TimbreBox.app`
(`xattr -dr com.apple.quarantine`); otherwise macOS would refuse to open it the first time.

If you install the disk image by hand:

1. Check it: `shasum -a 256 timbrebox_<version>_darwin_universal.dmg` must match its line in `checksums.txt`.
2. Copy `TimbreBox.app` into Applications and open it. When macOS says it cannot verify the app, click **Done**.
3. In System Settings → Privacy & Security, under Security, click **Open Anyway** next to "TimbreBox was blocked",
   then open TimbreBox again and choose **Open**. On macOS 14 and earlier, Control-click the app and choose **Open**
   also works.

Instead of steps 2–3 you can run `xattr -dr com.apple.quarantine /Applications/TimbreBox.app`. macOS remembers the
choice until you replace the app by hand.

The Windows app is not signed either. Check the `.zip` against `checksums.txt`
(`Get-FileHash timbrebox_<version>_windows_amd64.zip`); if SmartScreen stops `timbrebox_app.exe`, choose
**More info** → **Run anyway**.
