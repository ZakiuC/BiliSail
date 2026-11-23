import '../api_client.dart';
import '../app_profile.dart';
import '../mappers/dash_audio_parser.dart';
import '../models.dart';

/// Android App JSON playback, kept separate from Web Cookie/WBI playback.
///
/// The caller supplies the App device identity and optional App access token.
/// No Web cookies are copied into this channel and no entitlement is inferred
/// from the requested quality or trial flags.
final class AppPlaybackClient {
  AppPlaybackClient(this.api);

  final BiliApiClient api;
  static const _endpoint = 'app_playurl';

  Future<ApiPlayInfo> getPlayInfo(
    String bvid,
    String cid, {
    int qn = 80,
    String language = '',
    int productionType = 0,
    bool unlockHighestBitrate = false,
    bool unlimitedQualityTrial = false,
    required String buvid,
    String? accessToken,
    AppDeviceInfo? deviceInfo,
    ApiRequestContext? context,
  }) => _getPlayInfo(
    bvid,
    cid,
    qn: unlockHighestBitrate ? 127 : qn,
    language: language,
    productionType: productionType,
    unlimitedQualityTrial: unlimitedQualityTrial,
    buvid: buvid,
    accessToken: accessToken,
    deviceInfo: deviceInfo,
    context: context,
  );

  /// Explicit video-only preview. Trial flags and audio requirements do not
  /// apply here, but the server preview marker remains visible to the caller.
  Future<ApiPlayInfo> getVideoPreviewInfo(
    String bvid,
    String cid, {
    required String buvid,
    String? accessToken,
    AppDeviceInfo? deviceInfo,
    ApiRequestContext? context,
  }) => _getPlayInfo(
    bvid,
    cid,
    qn: 32,
    preview: true,
    buvid: buvid,
    accessToken: accessToken,
    deviceInfo: deviceInfo,
    context: context,
  );

  Future<ApiPlayInfo> _getPlayInfo(
    String bvid,
    String cid, {
    required int qn,
    bool preview = false,
    String language = '',
    int productionType = 0,
    bool unlimitedQualityTrial = false,
    required String buvid,
    String? accessToken,
    AppDeviceInfo? deviceInfo,
    ApiRequestContext? context,
  }) async {
    _validateTarget(bvid, cid, qn, language, productionType, buvid);
    final active = api.boundedReadContext(context);
    // Capture device facts once so the signed query and User-Agent cannot
    // describe different devices within a single logical read.
    final device = deviceInfo ?? await api.appDeviceInfo(context: active);
    final data = await api.requestAppJson(
      '/x/player/playurl',
      {
        'bvid': bvid,
        'cid': cid,
        'buvid': buvid,
        'qn': '$qn',
        'fnver': '0',
        'fnval': preview ? '2000' : '4048',
        'fourk': '1',
        'force_host': '2',
        'build': AppProfile.build,
        'mobi_app': AppProfile.mobiApp,
        'platform': 'android',
        'device': 'pad',
        'device_name': device.model,
        'network': device.network,
        if (!preview) ...{
          'voice_balance': '1',
          'cur_language': language,
          'cur_production_type': '$productionType',
          if (unlimitedQualityTrial) ...{
            'is_need_trial': '1',
            'is_need_view_info': '1',
            'try_look': '1',
          },
        },
        if (preview) 'need_fragment': 'false',
      },
      endpoint: _endpoint,
      buvid: buvid,
      accessToken: accessToken,
      deviceInfo: device,
      context: active,
    );
    return _parse(data, preview: preview);
  }

  static void _validateTarget(
    String bvid,
    String cid,
    int qn,
    String language,
    int productionType,
    String buvid,
  ) {
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid) ||
        !RegExp(r'^[1-9][0-9]{0,19}$').hasMatch(cid) ||
        qn < 1 ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(buvid) ||
        !const [0, 1, 2].contains(productionType) ||
        (productionType == 0) != language.isEmpty ||
        language.length > 32 ||
        (language.isNotEmpty &&
            !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(language))) {
      throw ArgumentError('Invalid App play target');
    }
  }

  static ApiPlayInfo _parse(
    Map<String, Object?> data, {
    required bool preview,
  }) {
    final isPreview =
        data['is_preview'] == true || _int(data['is_preview']) == 1;
    // A quality trial is never a complete source. Check this before DASH so a
    // short preview with plausible tracks cannot pass as the full video.
    if (isPreview && !preview) {
      throw const ApiFailure(ApiFailureCategory.permission, _endpoint);
    }
    final rawDash = data['dash'];
    if (rawDash == null) {
      throw const ApiFailure(ApiFailureCategory.unavailable, _endpoint);
    }
    final dash = _map(rawDash);
    final videos = _list(
      dash['video'],
    ).take(64).map((value) => _track(_map(value))).toList();
    final audios = preview
        ? const <ApiMediaTrack>[]
        : dashAudioEntries(dash, _endpoint).map(_track).toList();
    final dolby = _optionalMap(dash['dolby']);
    final silent =
        !preview &&
        audios.isEmpty &&
        dash.containsKey('audio') &&
        dash['audio'] == null &&
        dash.containsKey('flac') &&
        dash['flac'] == null &&
        _int(dolby?['type']) == 0 &&
        dolby?.containsKey('audio') == true &&
        dolby?['audio'] == null;
    if (videos.isEmpty || !preview && audios.isEmpty && !silent) {
      throw const ApiFailure(ApiFailureCategory.unavailable, _endpoint);
    }
    return ApiPlayInfo(
      duration: _duration(data, dash),
      dashVideo: List<ApiMediaTrack>.unmodifiable(videos),
      dashAudio: List<ApiMediaTrack>.unmodifiable(audios),
      isIntentionallySilent: silent,
      isPreview: isPreview,
      acceptQuality: List<int>.unmodifiable(
        _list(
          data['accept_quality'] ?? const <Object?>[],
        ).take(64).map(_int).whereType<int>(),
      ),
      loudness: ApiAudioLoudness.parse(data['volume']),
      voices: _playbackVoices(data['language']),
      currentLanguage: _text(data['cur_language']) ?? '',
      productionType: _int(data['cur_production_type']) ?? 0,
    );
  }

  static Duration _duration(
    Map<String, Object?> data,
    Map<String, Object?> dash,
  ) {
    final seconds = _number(dash['duration']);
    final milliseconds = seconds == null
        ? _int(data['timelength']) ?? 0
        : seconds.isFinite
        ? (seconds * 1000).round()
        : 0;
    return Duration(milliseconds: milliseconds.clamp(0, 86400000));
  }

  static ApiMediaTrack _track(Map<String, Object?> data) {
    final url = _uri(data['baseUrl'] ?? data['base_url']);
    final id = _int(data['id']);
    if (url == null || id == null) {
      throw const ApiFailure(ApiFailureCategory.protocol, _endpoint);
    }
    return ApiMediaTrack(
      id: id,
      url: url,
      backupUrls: List<Uri>.unmodifiable(
        _list(
          data['backupUrl'] ?? data['backup_url'] ?? const <Object?>[],
        ).take(16).map(_uri).whereType<Uri>(),
      ),
      bandwidth: _int(data['bandwidth']) ?? 0,
      mimeType: _text(data['mimeType'] ?? data['mime_type']) ?? '',
      codecs: _text(data['codecs']) ?? '',
    );
  }

  static List<ApiPlaybackVoice> _playbackVoices(Object? value) {
    final language = _optionalMap(value);
    if (language == null || language['support'] != true) return const [];
    final items = language['items'];
    if (items is! List<Object?>) return const [];
    final voices = <ApiPlaybackVoice>[];
    final keys = <String>{};
    for (final value in items.take(32)) {
      final item = _optionalMap(value);
      if (item == null) continue;
      final code = _text(item['lang']);
      final type = _int(item['production_type']);
      if (code == null ||
          type == null ||
          !const [1, 2].contains(type) ||
          !keys.add('$type:$code')) {
        continue;
      }
      voices.add(
        ApiPlaybackVoice(
          languageCode: code,
          label: _text(item['title']) ?? code,
          productionType: type,
          subtitleLanguage: _text(item['subtitle_lang']) ?? '',
          videoDetext: item['video_detext'] == true,
          videoMouthShapeChange: item['video_mouth_shape_change'] == true,
        ),
      );
    }
    return List<ApiPlaybackVoice>.unmodifiable(voices);
  }
}

const _endpoint = 'app_playurl';

Map<String, Object?> _map(Object? value) => value is Map<String, Object?>
    ? value
    : throw const ApiFailure(ApiFailureCategory.protocol, _endpoint);

Map<String, Object?>? _optionalMap(Object? value) =>
    value is Map<String, Object?> ? value : null;

List<Object?> _list(Object? value) => value is List
    ? value
    : throw const ApiFailure(ApiFailureCategory.protocol, _endpoint);

String? _text(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) => value is int
    ? value
    : value is String
    ? int.tryParse(value)
    : null;

num? _number(Object? value) => value is num
    ? value
    : value is String
    ? num.tryParse(value)
    : null;

Uri? _uri(Object? value) {
  if (value is! String || value.isEmpty || value.length > 8192) return null;
  final uri = Uri.tryParse(value.startsWith('//') ? 'https:$value' : value);
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  if (uri.scheme == 'https') return uri;
  final host = uri.host.toLowerCase();
  if (uri.scheme == 'http' &&
      (host == 'hdslb.com' ||
          host.endsWith('.hdslb.com') ||
          host == 'bilibili.com' ||
          host.endsWith('.bilibili.com'))) {
    return uri.replace(scheme: 'https');
  }
  return null;
}
