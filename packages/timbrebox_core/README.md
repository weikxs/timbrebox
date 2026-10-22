# timbrebox_core

The UI-free, network-free, platform-free business core of TimbreBox. It fixes the
minimal boundary between source search and the player so the five-platform Flutter
shell, the desktop CLI, and future source adapters all share one set of logic.

## Boundaries

- `SourceRegistry` only dispatches enabled sources that declare the `search`
  capability, and runs at most two searches concurrently.
- `CancellationToken` is cooperative: adapters call `throwIfCancelled()` at
  network/parse boundaries; the registry starts no new source once cancelled.
- Adapters throw only `SourceException` to carry sanitized user-facing messages;
  unknown errors collapse into a generic failure string.
- `PlayerController` only projects playback state. Resource release after a 30s
  pause is driven by the platform shell calling `release()` — the core creates no
  timers, background tasks, or player instances.

## Verify

```bash
cd packages/timbrebox_core
dart analyze
dart test
```
