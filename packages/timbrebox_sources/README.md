# timbrebox_sources

The online music sources of TimbreBox as a package other apps can depend on:
the catalogs and stream resolvers (Audius, Radio Browser, Internet Archive,
YouTube, Bilibili, Douyin and TikTok pages), the loopback header proxy, the
network egress policy, LRC lyrics and the texts of their messages. Pure Dart
with `dart:io`; no Flutter.

## Boundaries

- `EgressPolicy` guards requests made for untrusted input (plugins and the
  stream URLs they return): http(s) only, public addresses only, and the
  connection goes to the exact address that was checked, on every redirect.
- Streams that need request headers are played through `StreamHeaderProxy`,
  which listens on 127.0.0.1 only and refuses foreign `Host` names.
- Messages come from `SourceStrings` in Simplified Chinese or English. An app
  sets `SourceStrings.english` to follow its own language setting.

## Verify

```bash
cd packages/timbrebox_sources
dart analyze --fatal-infos
dart test
```
