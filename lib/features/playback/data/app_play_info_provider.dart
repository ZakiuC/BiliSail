import 'package:bili_api/bili_api.dart';

import '../../../core/logging/core_diagnostic_log.dart';
import '../../../core/network/api_requests.dart';

typedef AppPlayurlIdentity = ({
  String buvid,
  String? accessToken,
  int revision,
});

abstract interface class AppPlayInfoProvider {
  Future<ApiPlayInfo> resolve({
    required String bvid,
    required String cid,
    required int quality,
    required String language,
    required int productionType,
    required bool unlimitedQualityTrial,
    required ApiRequestContext context,
  });
}

/// Production App playurl source backed by the existing secure identity store.
/// Callbacks avoid a playback -> feed data dependency and keep secrets out of
/// playback state, logs and persisted settings.
final class AppPlayInfoSource implements AppPlayInfoProvider {
  factory AppPlayInfoSource(
    BiliApiClient api,
    ApiRequests requests, {
    required Future<AppPlayurlIdentity> Function() loadIdentity,
    required int Function() identityRevision,
    required Future<void> Function() invalidateIdentity,
    ApiGrpcTransport? playViewTransport,
  }) => AppPlayInfoSource._(
    api,
    requests,
    loadIdentity,
    identityRevision,
    invalidateIdentity,
    playViewTransport,
  );

  AppPlayInfoSource._(
    this._api,
    this._requests,
    this._loadIdentity,
    this._identityRevision,
    this._invalidateIdentity,
    this._playViewTransport,
  );

  final BiliApiClient _api;
  final ApiRequests _requests;
  final Future<AppPlayurlIdentity> Function() _loadIdentity;
  final int Function() _identityRevision;
  final Future<void> Function() _invalidateIdentity;
  final ApiGrpcTransport? _playViewTransport;

  @override
  Future<ApiPlayInfo> resolve({
    required String bvid,
    required String cid,
    required int quality,
    required String language,
    required int productionType,
    required bool unlimitedQualityTrial,
    required ApiRequestContext context,
  }) async {
    final identity = await _loadIdentity();
    final playViewTransport = _playViewTransport;
    if (playViewTransport != null) {
      try {
        final result =
            await AppPlayViewClient(
              _api,
              transport: playViewTransport,
            ).getPlayInfo(
              bvid,
              cid,
              qn: quality,
              language: language,
              productionType: productionType,
              unlimitedQualityTrial: unlimitedQualityTrial,
              buvid: identity.buvid,
              accessToken: identity.accessToken,
              context: context,
            );
        _checkIdentity(identity, context);
        _recordProtocol('playview', result, quality, unlimitedQualityTrial);
        return result;
      } on ApiFailure catch (error) {
        _recordProtocol(
          'playview',
          null,
          quality,
          unlimitedQualityTrial,
          outcome: CoreDiagnosticOutcome.failed,
          error: error,
        );
        if (error.category == ApiFailureCategory.cancelled) rethrow;
        // Keep the older JSON endpoint as a compatibility fallback.
      }
    }
    try {
      final result = await AppPlaybackClient(_api).getPlayInfo(
        bvid,
        cid,
        qn: quality,
        language: language,
        productionType: productionType,
        unlimitedQualityTrial: unlimitedQualityTrial,
        buvid: identity.buvid,
        accessToken: identity.accessToken,
        context: context,
      );
      _checkIdentity(identity, context);
      _recordProtocol('json', result, quality, unlimitedQualityTrial);
      return result;
    } on ApiFailure catch (error) {
      _recordProtocol(
        'json',
        null,
        quality,
        unlimitedQualityTrial,
        outcome: CoreDiagnosticOutcome.failed,
        error: error,
      );
      if (error.category == ApiFailureCategory.authentication &&
          identity.accessToken != null &&
          identity.revision == _identityRevision() &&
          context.cancellation?.isCancelled != true &&
          context.sessionEpoch != null &&
          context.sessionEpoch == _requests.sessionEpoch) {
        await _invalidateIdentity();
      }
      rethrow;
    }
  }

  void _recordProtocol(
    String protocol,
    ApiPlayInfo? info,
    int quality,
    bool trial, {
    CoreDiagnosticOutcome outcome = CoreDiagnosticOutcome.success,
    Object? error,
  }) {
    _requests.diagnostics?.record(
      CoreDiagnosticEvent.appPlayInfoResolved,
      appProtocol: protocol,
      requestedQuality: quality,
      trialRequested: trial,
      videoQualities: info?.dashVideo.map((track) => track.id).toList(),
      audioQualities: info?.dashAudio.map((track) => track.id).toList(),
      outcome: outcome,
      error: error,
    );
  }

  void _checkIdentity(AppPlayurlIdentity identity, ApiRequestContext context) {
    if (identity.revision != _identityRevision() ||
        context.cancellation?.isCancelled == true ||
        context.sessionEpoch != _requests.sessionEpoch) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'app_playurl');
    }
  }
}
