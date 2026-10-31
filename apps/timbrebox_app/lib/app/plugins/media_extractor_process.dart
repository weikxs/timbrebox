import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'media_extraction_error.dart';
import 'media_tool_bundle.dart';

export 'media_extraction_error.dart';

abstract interface class MediaExtractionRunner {
  Future<String> run(List<String> arguments);
  void cancel();
  void dispose();
}

/// Optional, explicitly pinned local backend. Plugins never choose the binary,
/// environment or command-line switches. No download or background daemon.
final class PinnedMediaExtractionRunner implements MediaExtractionRunner {
  PinnedMediaExtractionRunner({
    this.executable = const String.fromEnvironment('TIMBREBOX_YTDLP_PATH'),
    this.expectedSha256 = const String.fromEnvironment(
      'TIMBREBOX_YTDLP_SHA256',
    ),
    this.bundleManifestSha256 = const String.fromEnvironment(
      'TIMBREBOX_MEDIA_BUNDLE_SHA256',
    ),
    this.deadline = const Duration(seconds: 20),
  });

  final String executable;
  final String expectedSha256;
  final String bundleManifestSha256;
  final Duration deadline;
  _ExtractionJob? _job;
  bool _disposed = false;
  static int _active = 0;

  static Never _fail(String code, String message) =>
      throw MediaExtractionException(code, message);

  @override
  Future<String> run(List<String> arguments) async {
    if (_disposed) _fail('extractor_disposed', 'Media extraction is closed.');
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      _fail(
        'extractor_unsupported',
        'This media backend is available on desktop only.',
      );
    }
    final bundled = bundleManifestSha256.isNotEmpty;
    if (bundled
        ? !RegExp(r'^[a-f0-9]{64}$').hasMatch(bundleManifestSha256) ||
              executable.isNotEmpty ||
              expectedSha256.isNotEmpty
        : executable.isEmpty ||
              !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(expectedSha256)) {
      _fail(
        'extractor_unconfigured',
        'The desktop media backend has not been configured and pinned.',
      );
    }
    if (_job != null || _active >= 2) {
      _fail('extractor_busy', 'The media backend is busy; retry shortly.');
    }
    final job = _ExtractionJob();
    _job = job;
    _active++;
    final task = _run(job, arguments).whenComplete(() async {
      job.cancel();
      await job.cleanTemporaryFiles();
      _active--;
      if (identical(_job, job)) _job = null;
    });
    try {
      return await task.timeout(
        deadline,
        onTimeout: () {
          job.cancel();
          _fail('extractor_timeout', 'Media extraction timed out.');
        },
      );
    } on MediaExtractionException {
      rethrow;
    } on FileSystemException {
      _fail(
        'extractor_unavailable',
        'The configured media backend cannot be read in this environment.',
      );
    } on ProcessException {
      _fail(
        'extractor_start_failed',
        'The configured media backend cannot start in this environment.',
      );
    } catch (_) {
      _fail(
        'extractor_failed',
        'The media backend failed; its raw output is hidden for privacy.',
      );
    }
  }

  Future<String> _run(_ExtractionJob job, List<String> arguments) async {
    final bundle = bundleManifestSha256.isEmpty
        ? null
        : await MediaToolBundle.load(
            bundleManifestSha256,
            checkCancelled: job.check,
          );
    job.check();
    final file = File(bundle?.supervisor ?? executable);
    if (!file.isAbsolute || !await file.exists()) {
      _fail(
        'extractor_unavailable',
        'The configured media backend is unavailable.',
      );
    }
    final canonical = File(await file.resolveSymbolicLinks());
    final stat = await canonical.stat();
    if (stat.type != FileSystemEntityType.file ||
        stat.size > 256 * 1024 * 1024) {
      _fail(
        'extractor_unavailable',
        'The configured media backend is not a supported executable file.',
      );
    }
    final digest = await sha256.bind(canonical.openRead()).first;
    if (digest.toString() !=
        (bundle?.supervisorSha256 ?? expectedSha256).toLowerCase()) {
      _fail(
        'extractor_integrity',
        'The media backend checksum does not match this build.',
      );
    }
    job.check();
    var commandArguments = arguments;
    if (bundle != null) {
      job.temporary = await Directory.systemTemp.createTemp('timbrebox-media-');
      job.check();
      final separator = arguments.indexOf('--');
      final offset = separator < 0 ? arguments.length : separator;
      commandArguments = [
        ...arguments.take(offset),
        '--js-runtimes',
        'deno:${bundle.runtime}',
        ...arguments.skip(offset),
      ];
    }
    final process = await Process.start(
      canonical.path,
      commandArguments,
      runInShell: false,
      workingDirectory: canonical.parent.path,
      includeParentEnvironment: false,
      environment: {
        'PATH': '',
        'PYTHONNOUSERSITE': '1',
        'PYTHONPATH': '',
        'PYTHONSAFEPATH': '1',
        if (job.temporary != null) ...{
          'TMPDIR': job.temporary!.path,
          'TMP': job.temporary!.path,
          'TEMP': job.temporary!.path,
          'DENO_DIR': '${job.temporary!.path}/deno-cache',
          'DENO_NO_UPDATE_CHECK': '1',
          'DENO_NO_PROMPT': '1',
        },
        if (Platform.isWindows && Platform.environment['SystemRoot'] != null)
          'SystemRoot': Platform.environment['SystemRoot']!,
      },
    );
    job.attach(process, supervised: bundle != null);
    if (job.cancelled) {
      job.cancel();
      // Drain both pipes even if cancellation raced Process.start.
      await Future.wait([
        process.stdout.drain<void>(),
        process.stderr.drain<void>(),
      ]);
      job.check();
    }
    await process.stdin.close();
    final output = BytesBuilder(copy: false);
    int stderrBytes = 0;
    MediaExtractionException? failure;
    void tooLarge() {
      failure = const MediaExtractionException(
        'extractor_output_limit',
        'The media backend response exceeded its limit.',
      );
      job.cancel();
    }

    final stdout = process.stdout.listen((bytes) {
      if (failure != null) return;
      if (output.length + bytes.length > 4 * 1024 * 1024) {
        tooLarge();
      } else {
        output.add(bytes);
      }
    });
    final stderr = process.stderr.listen((bytes) {
      stderrBytes += bytes.length;
      if (stderrBytes > 64 * 1024 && failure == null) tooLarge();
    });
    await Future.wait([stdout.asFuture<void>(), stderr.asFuture<void>()]);
    final exit = await process.exitCode;
    if (failure != null) throw failure!;
    job.check();
    if (exit != 0) {
      _fail(
        'extractor_failed',
        'The platform could not be resolved anonymously by this backend.',
      );
    }
    return utf8.decode(output.takeBytes());
  }

  @override
  void cancel() => _job?.cancel();

  @override
  void dispose() {
    _disposed = true;
    cancel();
  }
}

final class _ExtractionJob {
  Process? process;
  Directory? temporary;
  bool cancelled = false;
  bool _supervised = false;
  Timer? _forceKill;

  void attach(Process value, {required bool supervised}) {
    process = value;
    _supervised = supervised;
    unawaited(
      value.exitCode.then((_) {
        if (identical(process, value)) process = null;
        _forceKill?.cancel();
      }),
    );
  }

  void cancel() {
    cancelled = true;
    final active = process;
    if (active == null) return;
    if (!_supervised) {
      active.kill(ProcessSignal.sigkill);
    } else if (active.kill(ProcessSignal.sigterm)) {
      _forceKill ??= Timer(const Duration(seconds: 1), () {
        process?.kill(ProcessSignal.sigkill);
      });
    }
  }

  Future<void> cleanTemporaryFiles() async {
    final active = process;
    if (active != null) {
      try {
        await active.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        active.kill(ProcessSignal.sigkill);
        try {
          await active.exitCode.timeout(const Duration(seconds: 2));
        } on TimeoutException {
          /* Bounded teardown; no raw diagnostics. */
        }
      }
    }
    _forceKill?.cancel();
    final folder = temporary;
    if (folder != null) {
      try {
        await folder.delete(recursive: true);
      } on FileSystemException {
        /* No raw paths in logs or plugin errors. */
      }
    }
  }

  void check() {
    if (cancelled) {
      throw const MediaExtractionException(
        'extractor_cancelled',
        'Media extraction was cancelled.',
      );
    }
  }
}
