import 'dart:async';
import 'dart:io';

/// How long an idle keep-alive connection stays open in a long-lived client.
const pooledIdleTimeout = Duration(seconds: 15);

/// Waits up to [timeout] for a request to open on a long-lived client. A
/// request that opens after that is aborted, so it never holds a pooled
/// connection that nobody will use.
Future<HttpClientRequest> openWithin(
  Future<HttpClientRequest> pending,
  Duration timeout,
) => pending.timeout(
  timeout,
  onTimeout: () {
    pending.then((request) => request.abort(), onError: (Object _) {});
    throw TimeoutException('The request did not open in time.', timeout);
  },
);

/// Sends [request] and waits up to [timeout] for the response headers,
/// aborting the request (and its connection) when they do not arrive.
Future<HttpClientResponse> responseWithin(
  HttpClientRequest request,
  Duration timeout,
) => request.close().timeout(
  timeout,
  onTimeout: () {
    request.abort();
    throw TimeoutException('The response did not arrive in time.', timeout);
  },
);
