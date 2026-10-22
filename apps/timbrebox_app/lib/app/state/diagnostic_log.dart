/// Local, in-memory diagnostic log. Off by default; when the user enables it
/// from settings, playback/source events and errors are recorded to a capped
/// ring buffer that can be viewed and copied for troubleshooting. Nothing is
/// sent anywhere.
abstract final class DiagnosticLog {
  static bool enabled = false;
  static const _max = 300;
  static final List<String> _entries = [];

  static void record(String message) {
    if (!enabled) return;
    final now = DateTime.now();
    final stamp =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    _entries.add('[$stamp] $message');
    if (_entries.length > _max) _entries.removeAt(0);
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static String get text => _entries.join('\n');

  static void clear() => _entries.clear();
}
