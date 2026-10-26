import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/model/catalog_track.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';
import 'package:timbrebox_app/app/state/atomic_file.dart';
import 'package:timbrebox_app/app/state/player_control_server.dart';
import 'package:timbrebox_app/app/state/session_store.dart';

import 'support/test_player_engine.dart';

/// `POST /quit` used to call exit(0) right away, dropping the session save
/// and any file write still in flight.
void main() {
  test('quitting saves the session and waits for writes first', () async {
    final events = <String>[];
    final sessions = _SlowSessionStore(events);
    final controller = AppController(
      engine: TestPlayerEngine(),
      sessionStore: sessions,
    );
    addTearDown(controller.dispose);
    await controller.play(_track);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    events.clear();
    final root = await Directory.systemTemp.createTemp('quit');
    addTearDown(() => root.delete(recursive: true));
    unawaited(
      writeFileAtomically(File('${root.path}/settings.json'), '{}').then(
        (_) => events.add('write'),
      ),
    );
    final exited = Completer<int>();
    final server = PlayerControlServer(
      controller,
      // Never the real ~/.timbrebox/control.json, whatever quit() touches.
      endpointFile: File('${root.path}/control.json'),
      exit: (code) {
        events.add('exit');
        exited.complete(code);
      },
    );

    await server.quit();

    expect(await exited.future, 0);
    expect(events, hasLength(3));
    expect(events.last, 'exit');
    expect(events, containsAll(['session', 'write']));
  });
}

const _track = CatalogTrack(
  id: 'a',
  title: 'Track a',
  artist: 'Artist',
  sourceId: 'audius',
  sourceName: 'Audius',
  duration: Duration(minutes: 3),
  quality: 'public',
);

final class _SlowSessionStore implements SessionStore {
  _SlowSessionStore(this.events);

  final List<String> events;

  Future<void> _slowly() async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    events.add('session');
  }

  @override
  Future<void> save(
    List<CatalogTrack> queue,
    int currentIndex, {
    int positionMs = 0,
  }) => _slowly();

  @override
  Future<void> savePosition(int positionMs) => _slowly();

  @override
  Future<RestoredSession?> load() async => null;

  @override
  Future<void> clear() async {}
}
