import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/audio_quality.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/data/app_play_info_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '8K preference uses the whole App source with App request headers',
    () async {
      final web = _WebTransport();
      final app = _AppProvider(_appInfo());
      final repository = _repository(web, app);

      final media = await repository.resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 127,
        cancellation: RequestCancellation(),
      );

      expect(web.requestedQualities, [127]);
      expect(app.qualities, [127]);
      // The whole ladder comes from the App response; Web tracks stay apart
      // because App URLs are rejected when a Web Referer is attached.
      expect(media.qualities, [112, 120, 126]);
      expect(media.quality, 126);
      expect(media.video.codec, 'dvh1.05.06');
      expect(media.audioTracks.map((track) => track.quality), [
        AudioQualityPreference.aac192,
        AudioQualityPreference.aac132,
        AudioQualityPreference.aac64,
        AudioQualityPreference.lossless,
        AudioQualityPreference.dolby,
      ]);
      expect(
        media.selectAudioQuality(AudioQualityPreference.lossless).audio?.codec,
        'fLaC',
      );
      expect(
        media.selectAudioQuality(AudioQualityPreference.dolby).audio?.codec,
        'ec-3',
      );
      // App headers: BiliDroid UA and no Referer.
      expect(media.headers.containsKey('Referer'), isFalse);
      expect(media.headers['User-Agent'], contains('BiliDroid'));
      expect(media.headers['User-Agent'], contains('build/9000100'));
    },
  );

  test('an explicit 1080P+ choice plays 1080P+, never forced to 4K', () async {
    final web = _WebTransport();
    final app = _AppProvider(_appInfo());
    final media = await _repository(web, app, cdnStatus: 206).resolve(
      const VideoId('BV1VNxr63EZp'),
      '43202641987',
      quality: 112,
      cancellation: RequestCancellation(),
    );
    // The user's exact tier wins even while unlock ordering is active.
    expect(media.quality, 112);
    expect(media.qualities, contains(120));
  });

  test('ordinary 1080P does not add an App request', () async {
    final web = _WebTransport();
    final app = _AppProvider(_appInfo());
    final media = await _repository(web, app).resolve(
      const VideoId('BV1VNxr63EZp'),
      '43202641987',
      quality: 80,
      cancellation: RequestCancellation(),
    );
    expect(app.qualities, isEmpty);
    expect(media.qualities, [16, 32, 64, 80]);
    expect(media.quality, 80);
  });

  test('optional App failure retains the complete Web source', () async {
    final web = _WebTransport();
    final app = _AppProvider.error(
      const ApiFailure(ApiFailureCategory.network, 'app_playurl'),
    );
    final media = await _repository(web, app).resolve(
      const VideoId('BV1VNxr63EZp'),
      '43202641987',
      quality: 127,
      cancellation: RequestCancellation(),
    );
    expect(media.quality, 80);
    expect(media.qualities, [16, 32, 64, 80]);
    expect(media.audio, isNotNull);
    // The Web source keeps Web headers.
    expect(media.headers['Referer'], 'https://www.bilibili.com/');
  });

  test(
    'App can replace a Web permission refusal with complete media',
    () async {
      final web = _WebTransport(preview: true);
      final app = _AppProvider(_appInfo());
      final media = await _repository(web, app).resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 120,
        cancellation: RequestCancellation(),
      );
      expect(app.qualities, [120]);
      expect(media.quality, 120);
      expect(media.audio, isNotNull);
      // The App fallback source uses App headers without a Referer.
      expect(media.headers.containsKey('Referer'), isFalse);
      expect(media.headers['User-Agent'], contains('BiliDroid'));
    },
  );

  test('a preview-only App reply cannot replace the Web refusal', () async {
    final web = _WebTransport(preview: true);
    final app = _AppProvider(_appInfo(preview: true));
    await expectLater(
      _repository(web, app).resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 127,
        cancellation: RequestCancellation(),
      ),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.kind,
          'kind',
          AppFailureKind.permission,
        ),
      ),
    );
  });

  test(
    'a 403 high-tier CDN URL degrades to 1080P instead of failing',
    () async {
      final web = _WebTransport();
      final app = _AppProvider(_appInfo());
      final media = await _repository(web, app, cdnStatus: 403).resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 127,
        cancellation: RequestCancellation(),
      );
      expect(media.quality, 80);
      // Rejected App tiers are hidden so the menu never offers dead entries.
      expect(media.qualities, [16, 32, 64, 80]);
      // The Web fallback restores Web headers.
      expect(media.headers['Referer'], 'https://www.bilibili.com/');
    },
  );

  test('a playable high tier is kept when the probe succeeds', () async {
    final web = _WebTransport();
    final app = _AppProvider(_appInfo());
    final media = await _repository(web, app, cdnStatus: 206).resolve(
      const VideoId('BV1VNxr63EZp'),
      '43202641987',
      quality: 127,
      cancellation: RequestCancellation(),
    );
    expect(media.quality, 126);
  });
}

ApiPlaybackRepository _repository(
  _WebTransport web,
  AppPlayInfoProvider app, {
  int cdnStatus = 200,
}) {
  final requests = ApiRequests();
  final api = BiliApiClient(transport: web, sessionProvider: requests);
  addTearDown(api.close);
  web.cdnStatus = cdnStatus;
  return ApiPlaybackRepository(api, requests, appPlayInfo: app);
}

final class _AppProvider implements AppPlayInfoProvider {
  _AppProvider(this.info) : error = null;
  _AppProvider.error(this.error) : info = null;
  final ApiPlayInfo? info;
  final ApiFailure? error;
  final qualities = <int>[];

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
    qualities.add(quality);
    final failure = error;
    if (failure != null) throw failure;
    return info!;
  }
}

final class _WebTransport implements ApiTransport {
  _WebTransport({this.preview = false});
  final bool preview;
  var cdnStatus = 200;
  final requestedQualities = <int>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.host == 'cdn.example') {
      return ApiHttpResponse(cdnStatus, Uint8List(0), const {});
    }
    final Map<String, Object?> data = switch (uri.path) {
      '/x/web-interface/nav' => {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/${'b' * 32}.png',
        },
      },
      '/x/web-interface/view' => {
        'aid': '123',
        'bvid': 'BV1VNxr63EZp',
        'title': 'fixture',
        'pages': [
          {'cid': '43202641987', 'page': 1, 'part': 'P1'},
        ],
      },
      '/x/player/wbi/playurl' => () {
        requestedQualities.add(int.parse(uri.queryParameters['qn']!));
        return {
          'is_preview': preview ? 1 : 0,
          'accept_quality': [80, 64, 32, 16],
          'dash': {
            'duration': 60,
            'video': [
              for (final quality in [80, 64, 32, 16])
                {
                  'id': quality,
                  'base_url': 'https://cdn.example/web-$quality.m4s',
                  'codecs': 'avc1.640028',
                  'bandwidth': quality * 10000,
                },
            ],
            'audio': [
              {
                'id': 30280,
                'base_url': 'https://cdn.example/web-audio.m4s',
                'codecs': 'mp4a.40.2',
                'bandwidth': 192000,
              },
            ],
          },
        };
      }(),
      _ => throw StateError('Unexpected request ${uri.path}'),
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}

ApiPlayInfo _appInfo({bool preview = false}) => ApiPlayInfo(
  duration: const Duration(seconds: 60),
  dashVideo: [
    _track(126, 'dvh1.05.06'),
    _track(120, 'avc1.640032'),
    _track(112, 'avc1.640032'),
  ],
  dashAudio: [
    _track(30280, 'mp4a.40.2'),
    _track(30232, 'mp4a.40.29'),
    _track(30216, 'mp4a.40.5'),
    _track(30251, 'fLaC'),
    _track(30250, 'ec-3'),
  ],
  acceptQuality: const [126, 120, 112],
  isPreview: preview,
);

ApiMediaTrack _track(int id, String codec) => ApiMediaTrack(
  id: id,
  url: Uri.parse('https://cdn.example/app-$id-$codec.m4s'),
  backupUrls: const [],
  bandwidth: id * 1000,
  mimeType: id > 30000 ? 'audio/mp4' : 'video/mp4',
  codecs: codec,
);
