import 'package:meta/meta.dart';

/// Controls request/response prompt caching behavior with OpenAI Responses API.
@immutable
class OpenAICacheConfig {
  /// Creates a new cache configuration instance.
  const OpenAICacheConfig({
    this.enabled = false,
    this.sessionId,
    this.ttlSeconds = 0,
    this.cacheControl,
    this.trackMetrics = true,
  });

  /// Whether to enable caching for this request.
  final bool enabled;

  /// Unique session identifier (for per-session cache isolation).
  final String? sessionId;

  /// Time-to-live for cached content in seconds.
  final int ttlSeconds;

  /// Cache control strategy.
  final CacheControl? cacheControl;

  /// Whether to track cache metrics in metadata/logs.
  final bool trackMetrics;
}

/// Cache control strategies for OpenAI Responses.
enum CacheControl {
  /// Session-only cache.
  ephemeral,

  /// Cross-session cache (provider dependent).
  persistent,

  /// Bypass caching entirely at the provider.
  noStore,
}

/// Extension to get the header value for the cache control strategy.
extension CacheControlHeader on CacheControl {
  /// The header value for the cache control strategy.
  String get headerValue => switch (this) {
    CacheControl.ephemeral => 'ephemeral',
    CacheControl.persistent => 'public',
    CacheControl.noStore => 'no-store',
  };
}
