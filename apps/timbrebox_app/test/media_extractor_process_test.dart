import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/plugins/media_extractor_process.dart';

Matcher _code(String code) =>
    isA<MediaExtractionException>().having((e) => e.code, 'code', code);

void main() {
  test('unconfigured runner never starts a process', () async {
    final runner = PinnedMediaExtractionRunner(
      executable: '',
      expectedSha256: '',
    );
    addTearDown(runner.dispose);
    await expectLater(runner.run([]), throwsA(_code('extractor_unconfigured')));
  });

  test('relative executable paths are not accepted', () async {
    final runner = PinnedMediaExtractionRunner(
      executable: 'yt-dlp',
      expectedSha256: '0' * 64,
    );
    addTearDown(runner.dispose);
    await expectLater(runner.run([]), throwsA(_code('extractor_unavailable')));
  });

  test(
    'non-executable pinned files have a safe startup error',
    () async {
      final directory = await Directory.systemTemp.createTemp('pinned-tool-');
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/not-executable',
      ).writeAsString('test data');
      final hash = (await sha256.bind(file.openRead()).first).toString();
      final runner = PinnedMediaExtractionRunner(
        executable: file.path,
        expectedSha256: hash,
      );
      addTearDown(runner.dispose);
      await expectLater(
        runner.run([]),
        throwsA(
          isA<MediaExtractionException>()
              .having((e) => e.code, 'code', 'extractor_start_failed')
              .having(
                (e) => e.message,
                'privacy',
                isNot(contains(directory.path)),
              ),
        ),
      );
    },
    skip: Platform.isWindows,
  );

  test('a checksum mismatch refuses a local executable', () async {
    final runner = PinnedMediaExtractionRunner(
      executable: '/bin/echo',
      expectedSha256: '0' * 64,
    );
    addTearDown(runner.dispose);
    await expectLater(runner.run([]), throwsA(_code('extractor_integrity')));
  }, skip: Platform.isWindows);

  test(
    'verified process uses literal arguments, not a shell',
    () async {
      final file = File(await File('/bin/echo').resolveSymbolicLinks());
      final hash = (await sha256.bind(file.openRead()).first).toString();
      final runner = PinnedMediaExtractionRunner(
        executable: file.path,
        expectedSha256: hash,
      );
      addTearDown(runner.dispose);
      expect(
        await runner.run([r'$(touch should-not-exist); literal']),
        contains(r'$(touch should-not-exist); literal'),
      );
    },
    skip: Platform.isWindows,
  );

  test(
    'deadline terminates the process and does not reveal stderr',
    () async {
      final file = File(await File('/bin/sleep').resolveSymbolicLinks());
      final hash = (await sha256.bind(file.openRead()).first).toString();
      final runner = PinnedMediaExtractionRunner(
        executable: file.path,
        expectedSha256: hash,
        deadline: const Duration(milliseconds: 100),
      );
      addTearDown(runner.dispose);
      final watch = Stopwatch()..start();
      await expectLater(
        runner.run(['10']),
        throwsA(_code('extractor_timeout')),
      );
      expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
    },
    skip: Platform.isWindows,
  );

  test('explicit cancellation terminates an active process', () async {
    final file = File(await File('/bin/sleep').resolveSymbolicLinks());
    final hash = (await sha256.bind(file.openRead()).first).toString();
    final runner = PinnedMediaExtractionRunner(
      executable: file.path,
      expectedSha256: hash,
    );
    addTearDown(runner.dispose);
    final result = runner.run(['10']);
    final check = expectLater(result, throwsA(_code('extractor_cancelled')));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    runner.cancel();
    await check;
  }, skip: Platform.isWindows);
}
