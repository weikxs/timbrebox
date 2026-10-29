/// Whether a request's `Host` header names the loopback server on [port]
/// itself. Anything else reached us through a foreign name (DNS rebinding).
bool isLoopbackHost(String? host, int port) {
  final normalized = host?.toLowerCase();
  return normalized == '127.0.0.1:$port' || normalized == 'localhost:$port';
}
