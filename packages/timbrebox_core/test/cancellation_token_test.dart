import 'package:test/test.dart';
import 'package:timbrebox_core/timbrebox_core.dart';

void main() {
  test('asynchronous cancellation is lazy, reusable and idempotent', () async {
    final token = CancellationToken();
    final first = token.whenCancelled;
    expect(identical(first, token.whenCancelled), true);
    token.cancel();
    token.cancel();
    await first;
    expect(token.isCancelled, true);
    expect(token.throwIfCancelled, throwsA(isA<OperationCancelled>()));
  });
  test('subscribing after cancellation completes immediately', () async {
    final token = CancellationToken()..cancel();
    await token.whenCancelled;
  });
}
