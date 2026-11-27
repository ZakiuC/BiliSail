import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bili_api/bili_api.dart';

import '../domain/pgc_resolver_health.dart';

/// Anonymous resolver health check backed by the same client as playback.
///
/// The sample season is a region-limited title and the sample episode is a real
/// episode of it, so a passing check proves that the address returns
/// unrestricted episodes and a DASH source without login. Both samples are
/// replaced by the next one when the previous one is gone; a stale sample must
/// never be reported as a broken server.
final class BiliApiPgcResolverHealth implements PgcResolverHealthChecker {
  BiliApiPgcResolverHealth({
    ApiTransport Function()? transport,
    this.timeout = const Duration(seconds: 12),
    DateTime Function()? clock,
    this.samples = defaultSamples,
  }) : _transport = transport ?? DioApiTransport.new,
       _ownsTransport = transport == null,
       _clock = clock ?? DateTime.now;

  /// Region-limited titles verified on 2026-11-27, most recent first.
  static const defaultSamples = <(String seasonId, String episodeId)>[
    ('40664', '458195'),
    ('28049', '276323'),
  ];

  final ApiTransport Function() _transport;
  final bool _ownsTransport;
  final Duration timeout;
  final DateTime Function() _clock;

  /// Season and episode pairs used as live smoke tests, most recent first.
  final List<(String seasonId, String episodeId)> samples;

  @override
  Future<PgcResolverHealth> check({
    required String baseUrl,
    required String region,
  }) async {
    final uri = Uri.tryParse(baseUrl.trim());
    if (uri == null ||
        !uri.isAbsolute ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return const PgcResolverHealth.failed(failure: '地址无效');
    }
    final area = PgcResolverRegion.tryParse(region);
    if (area == null) return const PgcResolverHealth.failed(failure: '未知地区');
    final ApiTransport transport;
    final PgcResolver resolver;
    try {
      transport = _transport();
      resolver = PgcResolver(
        servers: {area: uri},
        defaultRegion: area,
        transport: transport,
        timeout: timeout,
        clock: _clock,
      );
    } on ArgumentError {
      return const PgcResolverHealth.failed(failure: '地址无效');
    }
    final started = _clock();
    Duration elapsed() => _clock().difference(started);
    try {
      for (final (seasonId, episodeId) in samples) {
        // resolveSeason/resolvePlayInfo swallow candidate failures and return
        // null; lastFailure explains which attempt ended the call.
        final season = await resolver.resolveSeason(
          seasonId: seasonId,
          requireEpisodes: true,
        );
        if (season == null) {
          final failure = resolver.lastFailure;
          // A delisted sample is not the server's fault; try the next pair.
          if (failure == null ||
              failure.category == ApiFailureCategory.notFound) {
            continue;
          }
          return PgcResolverHealth.failed(
            failure: _describe(failure),
            latency: elapsed(),
          );
        }
        final info = await resolver.resolvePlayInfo(episodeId, qn: 64);
        if (info == null) {
          final failure = resolver.lastFailure;
          return PgcResolverHealth(
            seasonReady: true,
            playbackReady: false,
            latency: elapsed(),
            failure: failure == null ? '取流无可用分轨' : _describe(failure),
          );
        }
        return PgcResolverHealth(
          seasonReady: true,
          playbackReady: true,
          latency: elapsed(),
        );
      }
      return PgcResolverHealth.failed(failure: '详情接口无有效数据', latency: elapsed());
    } on ApiFailure catch (error) {
      // Cancellation and an exhausted deadline propagate out of the resolver.
      return PgcResolverHealth.failed(
        failure: _describe(error),
        latency: elapsed(),
      );
    } finally {
      resolver.close();
      // The resolver never closes a borrowed transport, so a transport this
      // instance created must be released here.
      if (_ownsTransport && transport is DioApiTransport) transport.close();
    }
  }

  static String _describe(ApiFailure error) {
    return switch (error.category) {
      ApiFailureCategory.cancelled => '已取消',
      ApiFailureCategory.timeout => '连接超时',
      ApiFailureCategory.network => '网络不可达',
      ApiFailureCategory.http => 'HTTP ${error.httpStatus ?? '错误'}',
      ApiFailureCategory.rateLimited => '服务器限流',
      ApiFailureCategory.authentication => '服务器要求账号凭据',
      ApiFailureCategory.permission => '服务器返回地区拒绝',
      ApiFailureCategory.notFound => '样例剧集已下架',
      ApiFailureCategory.protocol => '响应格式不符',
      ApiFailureCategory.unavailable => '无可用取流',
    };
  }
}

/// Null when the host build supplies no checker, so the settings page hides the
/// check actions instead of showing an always-failing button.
final pgcResolverHealthProvider = Provider<PgcResolverHealthChecker?>(
  (ref) => null,
);
