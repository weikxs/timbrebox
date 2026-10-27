import 'package:flutter_test/flutter_test.dart';
import 'package:timbrebox_app/app/design/software_rendering.dart';
import 'package:timbrebox_app/app/state/app_controller.dart';

import 'support/test_player_engine.dart';

bool _decide({
  bool isLinux = true,
  List<String> arguments = const [],
  Map<String, String> environment = const {},
}) => isSoftwareRendering(
  isLinux: isLinux,
  arguments: arguments,
  environment: environment,
);

String _renderer(String name) => '$glRendererArgumentPrefix$name';

void main() {
  group('isSoftwareRendering', () {
    test('Mesa llvmpipe, softpipe and SwiftShader count as software', () {
      for (final name in [
        'llvmpipe (LLVM 15.0.7, 256 bits)',
        'softpipe',
        'Google SwiftShader',
        'Software Rasterizer (swrast)',
      ]) {
        expect(_decide(arguments: [_renderer(name)]), isTrue, reason: name);
      }
    });

    test('a hardware renderer keeps the effects', () {
      for (final name in [
        'Mesa Intel(R) UHD Graphics 620 (KBL GT2)',
        'AMD Radeon RX 6600 (radeonsi, navi23, LLVM 15.0.7, DRM 3.49)',
        'NVIDIA GeForce RTX 3060/PCIe/SSE2',
        'V3D 4.2',
      ]) {
        expect(_decide(arguments: [_renderer(name)]), isFalse, reason: name);
      }
    });

    test('no GL context at all counts as software', () {
      expect(_decide(arguments: [_renderer('')]), isTrue);
    });

    test('a runner that did not probe means a GPU is assumed', () {
      expect(_decide(arguments: ['--other']), isFalse);
    });

    test('LIBGL_ALWAYS_SOFTWARE forces software', () {
      final environment = {'LIBGL_ALWAYS_SOFTWARE': '1'};
      expect(_decide(environment: environment), isTrue);
      expect(
        _decide(
          arguments: [_renderer('NVIDIA GeForce RTX 3060')],
          environment: {'LIBGL_ALWAYS_SOFTWARE': 'true'},
        ),
        isTrue,
      );
      expect(_decide(environment: {'LIBGL_ALWAYS_SOFTWARE': '0'}), isFalse);
    });

    test('never on macOS, Windows or mobile', () {
      expect(
        _decide(
          isLinux: false,
          arguments: [_renderer('llvmpipe')],
          environment: {'LIBGL_ALWAYS_SOFTWARE': '1'},
        ),
        isFalse,
      );
    });
  });

  group('effects under software rendering', () {
    test('are off by default without changing the saved preference', () {
      final controller = AppController(
        engine: TestPlayerEngine(),
        softwareRendering: true,
      );
      addTearDown(controller.dispose);

      expect(controller.softwareRendering, isTrue);
      expect(controller.reducedEffects, isTrue);
      expect(controller.settingsSnapshot['reducedEffects'], isFalse);
      expect(controller.settingsSnapshot['effectsWithoutGpu'], isFalse);
    });

    test('can be forced back on, and off again', () {
      final controller = AppController(
        engine: TestPlayerEngine(),
        softwareRendering: true,
      );
      addTearDown(controller.dispose);

      controller.setReducedEffects(false);
      expect(controller.reducedEffects, isFalse);
      expect(controller.settingsSnapshot['reducedEffects'], isFalse);
      expect(controller.settingsSnapshot['effectsWithoutGpu'], isTrue);

      controller.setReducedEffects(true);
      expect(controller.reducedEffects, isTrue);
      expect(controller.settingsSnapshot['reducedEffects'], isTrue);
      expect(controller.settingsSnapshot['effectsWithoutGpu'], isFalse);
    });

    test('stay on with a GPU unless the user reduces them', () {
      final controller = AppController(engine: TestPlayerEngine());
      addTearDown(controller.dispose);

      expect(controller.reducedEffects, isFalse);
      controller.setReducedEffects(true);
      expect(controller.reducedEffects, isTrue);
      expect(controller.settingsSnapshot['effectsWithoutGpu'], isFalse);
    });
  });
}
