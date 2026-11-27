/// Anonymous smoke-test result for one resolver address.
///
/// The checker replays the same two calls the playback path uses (season detail
/// then playurl), so [usable] means the address can actually serve an episode
/// without account credentials instead of just answering HTTP.
final class PgcResolverHealth {
  const PgcResolverHealth({
    required this.seasonReady,
    required this.playbackReady,
    required this.latency,
    this.failure,
  });

  const PgcResolverHealth.failed({
    required this.failure,
    this.latency = Duration.zero,
  }) : seasonReady = false,
       playbackReady = false;

  /// Season detail returned episodes that are not area-limited.
  final bool seasonReady;

  /// playurl returned a DASH source with both video and audio tracks.
  final bool playbackReady;

  /// Wall-clock time of the whole check, including every fallback path.
  final Duration latency;

  /// Short user-facing reason when something failed; null when [usable].
  final String? failure;

  bool get usable => seasonReady && playbackReady;

  /// Detail works but playback does not, e.g. a server that only proxies
  /// season metadata or demands an access_key.
  bool get partial => seasonReady && !playbackReady;

  /// One-line summary for the settings surface.
  String get summary {
    if (usable) {
      return '可用（${(latency.inMilliseconds / 1000).toStringAsFixed(1)} 秒）';
    }
    if (partial) return '仅详情可用：${failure ?? '取流被拒绝'}';
    return '不可用：${failure ?? '无响应'}';
  }
}

/// Runs the anonymous season/playurl check used by the settings page.
abstract interface class PgcResolverHealthChecker {
  Future<PgcResolverHealth> check({
    required String baseUrl,
    required String region,
  });
}
