# timbrebox_playback

The playback backend of TimbreBox as a Flutter package: the media_kit (libmpv)
`PlayerBackend`, the audio sources it plays and the position sampler. It
depends on `media_kit` only; each app picks its own native libraries
(`media_kit_libs_audio` or `media_kit_libs_video`).

## Verify

```bash
cd packages/timbrebox_playback
flutter analyze
flutter test
```
