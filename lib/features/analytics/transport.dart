/// The analytics transport boundary (PRD §8 Unit 12: "batched HTTPS to a
/// self-controlled endpoint... queued offline"; §9 A-5: self-hosted
/// endpoint is the default posture).
///
/// [AnalyticsTransport] is the seam the whole feature is tested through:
/// `EventQueue` and `AnalyticsClient` only ever see this interface, so the
/// test suite substitutes a recording fake and no test ever opens a
/// socket. [HttpsAnalyticsTransport] is the one production implementation
/// — a thin `dart:io` adapter with no third-party tracker SDK anywhere
/// near it.
library;

import 'dart:convert';
import 'dart:io';

/// The outcome of one batch send.
///
/// Deliberately binary: the queue's only decision is "did this batch land,
/// or should it stay queued for the next flush?". A failure is not an
/// error to surface to the user — offline is a normal state.
enum TransportResult {
  /// The batch was accepted by the endpoint and may be dropped locally.
  success,

  /// The batch was not accepted (offline, timeout, server error). It stays
  /// queued.
  failure,
}

/// Sends batches of analytics payloads somewhere.
abstract class AnalyticsTransport {
  /// Sends one batch of already-validated wire payloads.
  ///
  /// Must never throw: connectivity problems are reported as
  /// [TransportResult.failure].
  Future<TransportResult> send(List<Map<String, Object?>> batch);
}

/// A transport that drops everything on the floor and reports success.
///
/// Useful as the default in builds that have no endpoint configured yet
/// (OQ-6) — the queue then behaves exactly as if the events had shipped,
/// so nothing accumulates on the device.
class NullAnalyticsTransport implements AnalyticsTransport {
  /// Creates a no-op transport.
  const NullAnalyticsTransport();

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async =>
      TransportResult.success;
}

/// Posts batches as JSON over HTTPS to a self-controlled endpoint (A-5).
///
/// Correct-by-inspection rather than by test: nothing in the suite opens a
/// network connection, so this class is kept as small as it can possibly
/// be. It adds no headers that could identify a device or user, sends no
/// cookies, and treats any non-2xx response or any I/O failure as
/// [TransportResult.failure] so the batch stays queued for a later flush.
///
/// The endpoint URL itself is OQ-6 (blocks pilot distribution, not build).
class HttpsAnalyticsTransport implements AnalyticsTransport {
  /// Creates a transport posting to [endpoint], which must be `https`.
  ///
  /// [httpClient] is injectable so a localhost fixture server can be used
  /// in an integration check; production passes nothing.
  HttpsAnalyticsTransport({
    required this.endpoint,
    HttpClient? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : _httpClient = httpClient ?? HttpClient() {
    if (endpoint.scheme != 'https') {
      throw ArgumentError.value(
        endpoint.toString(),
        'endpoint',
        'analytics endpoint must be https (PRD §8 Unit 12)',
      );
    }
  }

  /// The self-controlled collection endpoint.
  final Uri endpoint;

  /// How long one batch POST may take before it counts as a failure.
  final Duration timeout;

  final HttpClient _httpClient;

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async {
    if (batch.isEmpty) return TransportResult.success;
    try {
      final body = utf8.encode(jsonEncode(<String, Object?>{'events': batch}));
      final request = await _httpClient.postUrl(endpoint).timeout(timeout);
      request.headers
        ..contentType = ContentType.json
        ..contentLength = body.length;
      request.cookies.clear();
      request.followRedirects = false;
      request.add(body);
      final response = await request.close().timeout(timeout);
      // Drain so the connection can be reused; the body is not used.
      await response.drain<void>().timeout(timeout);
      final ok = response.statusCode >= 200 && response.statusCode < 300;
      return ok ? TransportResult.success : TransportResult.failure;
    } on Object {
      // Offline, DNS failure, TLS failure, timeout, malformed response:
      // all the same decision — keep the batch queued.
      return TransportResult.failure;
    }
  }

  /// Releases the underlying HTTP client.
  void close() => _httpClient.close(force: true);
}
