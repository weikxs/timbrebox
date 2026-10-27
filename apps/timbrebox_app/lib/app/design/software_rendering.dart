/// Whether the window is drawn without a GPU, where every frame of a blur or
/// an animation costs real CPU (Mesa's llvmpipe drew the frosted glass at
/// 150-200% CPU while playing).
///
/// The Linux runner probes OpenGL once before the engine starts and passes
/// the renderer it found as `--timbrebox-gl-renderer=<GL_RENDERER>` (empty
/// when no GL context could be made). Other platforms pass nothing and are
/// never treated as software rendered: there is no cheap, reliable signal
/// there, and their desktops practically always have a GPU.
library;

/// The argument the Linux runner adds to the Dart entrypoint arguments.
const glRendererArgumentPrefix = '--timbrebox-gl-renderer=';

/// Substrings (lower case) of OpenGL renderer names that rasterize on the CPU.
const _softwareRenderers = ['llvmpipe', 'softpipe', 'swiftshader', 'swrast'];

/// Decides from the runner's [arguments] and the process [environment].
bool isSoftwareRendering({
  required bool isLinux,
  required List<String> arguments,
  required Map<String, String> environment,
}) {
  if (!isLinux) return false;
  final forced = environment['LIBGL_ALWAYS_SOFTWARE']?.trim().toLowerCase();
  if (forced == '1' || forced == 'true') return true;
  final renderer = _glRenderer(arguments);
  if (renderer == null) return false; // Not probed: assume a GPU.
  if (renderer.isEmpty) return true; // No GL context could be made at all.
  final name = renderer.toLowerCase();
  return _softwareRenderers.any(name.contains);
}

String? _glRenderer(List<String> arguments) {
  for (final argument in arguments) {
    if (argument.startsWith(glRendererArgumentPrefix)) {
      return argument.substring(glRendererArgumentPrefix.length).trim();
    }
  }
  return null;
}
