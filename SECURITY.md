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
