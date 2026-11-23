import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _bvid = 'BV1q6ad6NEVK';
const _cid = '42328985110';
const _buvid = 'XY1234567890ABCDEF1234567890ABCDEF12345';

const _video127 = <String, Object?>{
  'id': 127,
  'baseUrl': 'https://cdn.example/video127.m4s',
  'backupUrl': [
    'http://upos-sz-mirror.example.hdslb.com/video127.m4s',
    'https://backup.example/video127.m4s',
  ],
  'bandwidth': 9000000,
  'mimeType': 'video/mp4',
  'codecs': 'avc1.640034',
};
const _video120 = <String, Object?>{
  'id': '120',
  'base_url': '//cdn.example/video120.m4s',
  'backup_url': <Object?>[],
  'bandwidth': '5000000',
  'mime_type': 'video/mp4',
  'codecs': 'hev1.1.6.L153.B0',
};
const _audio = <String, Object?>{
  'id': 30280,
  'base_url': 'https://cdn.example/audio.m4s',
  'backup_url': <Object?>[],
  'bandwidth': 128000,
  'mime_type': 'audio/mp4',
  'codecs': 'mp4a.40.2',
};
const _dash = <String, Object?>{
  'duration': 123.456,
  'video': [_video127, _video120],
  'audio': [_audio],
};
const _data = <String, Object?>{
  'accept_quality': [127, '120', 80],
  'timelength': 123456,
  'cur_language': 'en',
  'cur_production_type': 1,
  'language': {
    'support': true,
    'items': [
      {
        'lang': 'en',
        'title': 'English',
        'production_type': 1,
        'subtitle_lang': 'en-US',
        'video_detext': true,
      },
    ],
  },
  'dash': _dash,
};

void main() {
  test(
    'App high-quality request signs one device snapshot and parses full DASH',
    () async {
      final transport = _Transport();
      var deviceReads = 0;
      final api = _client(
        transport,
        clock: () => DateTime.fromMillisecondsSinceEpoch(1234567890000),
        loadAppDevice: () async {
          deviceReads++;
          return const AppDeviceInfo(
            model: 'Pixel 9',
            osVersion: '16',
            network: 'mobile',
          );
        },
      );
      api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=web-fixture; Domain=bilibili.com; Path=/; Secure',
      ]);

      final info = await AppPlaybackClient(api).getPlayInfo(
        _bvid,
        _cid,
        qn: 16,
        language: 'en',
        productionType: 1,
        unlockHighestBitrate: true,
        unlimitedQualityTrial: true,
        buvid: _buvid,
        accessToken: 'fixture-app-token',
      );

      expect(deviceReads, 1);
      final attempt = transport.attempts.single;
      expect(attempt.uri.scheme, 'https');
      expect(attempt.uri.host, 'api.bilibili.com');
      expect(attempt.uri.path, '/x/player/playurl');
      final query = attempt.uri.queryParameters;
      expect(query, {
        'access_key': 'fixture-app-token',
        'appkey': 'dfca71928277209b',
        'buvid': _buvid,
        'bvid': _bvid,
        'build': '2001100',
        'cid': _cid,
        'cur_language': 'en',
        'cur_production_type': '1',
        'device': 'pad',
        'device_name': 'Pixel 9',
        'fnval': '4048',
        'fnver': '0',
        'force_host': '2',
        'fourk': '1',
        'is_need_trial': '1',
        'is_need_view_info': '1',
        'mobi_app': 'android_hd',
        'network': 'mobile',
        'platform': 'android',
        'qn': '127',
        'sign': query['sign'],
        'try_look': '1',
        'ts': '1234567890',
        'voice_balance': '1',
      });
      expect(query['sign'], matches(r'^[0-9a-f]{32}$'));
      expect(attempt.headers['buvid'], _buvid);
      expect(attempt.headers['User-Agent'], contains('model/Pixel 9'));
      expect(attempt.headers['User-Agent'], contains('osVer/16 network/1'));
      expect(
        attempt.headers.keys.map((key) => key.toLowerCase()),
        isNot(contains('cookie')),
      );

      expect(info.acceptQuality, [127, 120, 80]);
      expect(info.duration, const Duration(milliseconds: 123456));
      expect(info.dashVideo.map((track) => track.id), [127, 120]);
      expect(info.dashVideo.first.bandwidth, 9000000);
      expect(info.dashVideo.first.backupUrls.first.scheme, 'https');
      expect(info.dashVideo.last.url.scheme, 'https');
      expect(info.dashVideo.last.mimeType, 'video/mp4');
      expect(info.dashAudio.single.id, 30280);
      expect(info.dashAudio.single.codecs, 'mp4a.40.2');
      expect(info.currentLanguage, 'en');
      expect(info.productionType, 1);
      expect(info.voices.single.languageCode, 'en');
      expect(info.voices.single.subtitleLanguage, 'en-US');
      expect(info.voices.single.videoDetext, isTrue);
      expect(info.isPreview, isFalse);
      expect(info.isIntentionallySilent, isFalse);
    },
  );

  test(
    'ordinary request keeps qn and omits trial and absent credentials',
    () async {
      final transport = _Transport();
      final api = _client(
        transport,
        loadAppDevice: () => throw StateError('must use supplied device'),
      );
      await AppPlaybackClient(api).getPlayInfo(
        _bvid,
        _cid,
        buvid: _buvid,
        deviceInfo: const AppDeviceInfo(),
      );
      final query = transport.attempts.single.uri.queryParameters;
      expect(query['qn'], '80');
      expect(query['fnval'], '4048');
      expect(query['fourk'], '1');
      expect(query.containsKey('access_key'), isFalse);
      expect(query.containsKey('try_look'), isFalse);
      expect(query.containsKey('is_need_trial'), isFalse);
      expect(query.containsKey('is_need_view_info'), isFalse);
    },
  );

  test('invalid targets and device identities fail before any I/O', () async {
    final transport = _Transport();
    final client = AppPlaybackClient(_client(transport));
    final calls = <Future<ApiPlayInfo> Function()>[
      () => client.getPlayInfo('invalid', _cid, buvid: _buvid),
      () => client.getPlayInfo(_bvid, '0', buvid: _buvid),
      () => client.getPlayInfo(_bvid, _cid, qn: 0, buvid: _buvid),
      () => client.getPlayInfo(_bvid, _cid, buvid: 'bad'),
      () => client.getPlayInfo(
        _bvid,
        _cid,
        language: 'en',
        productionType: 0,
        buvid: _buvid,
      ),
    ];
    for (final call in calls) {
      await expectLater(call(), throwsArgumentError);
    }
    expect(transport.attempts, isEmpty);
  });

  test('full playback rejects an is_preview DASH response', () async {
    final transport = _Transport(
      (uri, index) async => _response({..._data, 'is_preview': true}),
    );
    await expectLater(
      AppPlaybackClient(
        _client(transport),
      ).getPlayInfo(_bvid, _cid, unlimitedQualityTrial: true, buvid: _buvid),
      throwsA(
        isA<ApiFailure>()
            .having(
              (e) => e.category,
              'category',
              ApiFailureCategory.permission,
            )
            .having((e) => e.endpointId, 'endpoint', 'app_playurl'),
      ),
    );
    expect(transport.attempts, hasLength(1));
    expect(transport.attempts.single.uri.queryParameters['try_look'], '1');
  });

  test(
    'explicit video preview allows omitted audio but retains preview marker',
    () async {
      final transport = _Transport(
        (uri, index) async => _response({
          'accept_quality': [32],
          'is_preview': 1,
          'dash': const {
            'duration': 30,
            'video': [_video120],
          },
        }),
      );
      final info = await AppPlaybackClient(
        _client(transport),
      ).getVideoPreviewInfo(_bvid, _cid, buvid: _buvid);
      final query = transport.attempts.single.uri.queryParameters;
      expect(query['qn'], '32');
      expect(query['fnval'], '2000');
      expect(query['need_fragment'], 'false');
      expect(query.containsKey('voice_balance'), isFalse);
      expect(query.containsKey('try_look'), isFalse);
      expect(info.isPreview, isTrue);
      expect(info.dashVideo, hasLength(1));
      expect(info.dashAudio, isEmpty);
      expect(info.acceptQuality, [32]);
    },
  );

  test(
    'missing audio is incomplete unless every variant declares silence',
    () async {
      final videoOnly = <String, Object?>{
        'duration': 60,
        'video': [_video120],
      };
      final missing = _Transport(
        (uri, index) async => _response({..._data, 'dash': videoOnly}),
      );
      await expectLater(
        AppPlaybackClient(
          _client(missing),
        ).getPlayInfo(_bvid, _cid, buvid: _buvid),
        throwsA(_failure(ApiFailureCategory.unavailable)),
      );

      final silent = _Transport(
        (uri, index) async => _response({
          ..._data,
          'dash': {
            ...videoOnly,
            'audio': null,
            'flac': null,
            'dolby': {'type': 0, 'audio': null},
          },
        }),
      );
      final info = await AppPlaybackClient(
        _client(silent),
      ).getPlayInfo(_bvid, _cid, buvid: _buvid);
      expect(info.dashAudio, isEmpty);
      expect(info.isIntentionallySilent, isTrue);
    },
  );

  test('FLAC and Dolby variants use the shared DASH audio mapping', () async {
    final transport = _Transport(
      (uri, index) async => _response({
        ..._data,
        'dash': {
          'duration': 60,
          'video': [_video120],
          'audio': null,
          'flac': {'audio': _audio},
          'dolby': {
            'type': 1,
            'audio': [
              {..._audio, 'id': 30216},
            ],
          },
        },
      }),
    );
    final info = await AppPlaybackClient(
      _client(transport),
    ).getPlayInfo(_bvid, _cid, buvid: _buvid);
    expect(info.dashAudio.map((track) => track.id), [30280, 30216]);
    expect(info.isIntentionallySilent, isFalse);
  });

  test('malformed quality and track data remain protocol failures', () async {
    for (final data in [
      {..._data, 'accept_quality': '127'},
      {
        ..._data,
        'dash': {
          ..._dash,
          'video': [
            {..._video127, 'baseUrl': 'file:///tmp/video.m4s'},
          ],
        },
      },
    ]) {
      final transport = _Transport((uri, index) async => _response(data));
      await expectLater(
        AppPlaybackClient(
          _client(transport),
        ).getPlayInfo(_bvid, _cid, buvid: _buvid),
        throwsA(_failure(ApiFailureCategory.protocol)),
      );
    }
  });

  test(
    'business and HTTP failures retain their original classification',
    () async {
      final business = _Transport(
        (uri, index) async => _response(null, code: -404),
      );
      await expectLater(
        AppPlaybackClient(
          _client(business),
        ).getPlayInfo(_bvid, _cid, buvid: _buvid),
        throwsA(
          isA<ApiFailure>()
              .having(
                (e) => e.category,
                'category',
                ApiFailureCategory.permission,
              )
              .having((e) => e.endpointId, 'endpoint', 'app_playurl')
              .having((e) => e.businessCode, 'businessCode', -404),
        ),
      );
      expect(business.attempts, hasLength(1));

      final http = _Transport(
        (uri, index) async => _response(null, status: 403),
      );
      await expectLater(
        AppPlaybackClient(
          _client(http),
        ).getPlayInfo(_bvid, _cid, buvid: _buvid),
        throwsA(
          isA<ApiFailure>()
              .having(
                (e) => e.category,
                'category',
                ApiFailureCategory.authentication,
              )
              .having((e) => e.httpStatus, 'httpStatus', 403),
        ),
      );
      expect(http.attempts, hasLength(1));
    },
  );

  test('unexpected transport and device errors are not replaced', () async {
    final transportError = StateError('fixture transport');
    final transport = _Transport((uri, index) => Future.error(transportError));
    await expectLater(
      AppPlaybackClient(
        _client(transport),
      ).getPlayInfo(_bvid, _cid, buvid: _buvid),
      throwsA(same(transportError)),
    );

    final deviceError = StateError('fixture device');
    final api = _client(
      _Transport(),
      loadAppDevice: () async => throw deviceError,
    );
    await expectLater(
      AppPlaybackClient(api).getPlayInfo(_bvid, _cid, buvid: _buvid),
      throwsA(same(deviceError)),
    );
  });

  test(
    'remaining deadline caps a stalled read and cancels its attempt',
    () async {
      final transport = _Transport(
        (uri, index) => Completer<ApiHttpResponse>().future,
      );
      final deadline = DateTime.now().add(const Duration(milliseconds: 50));
      await expectLater(
        AppPlaybackClient(_client(transport)).getPlayInfo(
          _bvid,
          _cid,
          buvid: _buvid,
          context: ApiRequestContext(deadline: deadline),
        ),
        throwsA(_failure(ApiFailureCategory.timeout)),
      );
      expect(transport.attempts, hasLength(1));
      expect(
        transport.attempts.single.timeout,
        lessThanOrEqualTo(const Duration(milliseconds: 50)),
      );
      expect(transport.attempts.single.cancellation?.isCancelled, isTrue);
    },
  );

  test(
    'caller cancellation interrupts the network read without retrying',
    () async {
      final transport = _Transport(
        (uri, index) => Completer<ApiHttpResponse>().future,
      );
      final cancellation = ApiCancellation();
      final read = AppPlaybackClient(_client(transport)).getPlayInfo(
        _bvid,
        _cid,
        buvid: _buvid,
        context: ApiRequestContext(cancellation: cancellation),
      );
      final cancelled = expectLater(
        read,
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      await cancelled;
      expect(transport.attempts, hasLength(1));
      expect(transport.attempts.single.cancellation?.isCancelled, isTrue);
    },
  );

  test('caller cancellation also interrupts a pending device read', () async {
    final device = Completer<AppDeviceInfo>();
    final api = _client(_Transport(), loadAppDevice: () => device.future);
    final cancellation = ApiCancellation();
    final read = AppPlaybackClient(api).getPlayInfo(
      _bvid,
      _cid,
      buvid: _buvid,
      context: ApiRequestContext(cancellation: cancellation),
    );
    final cancelled = expectLater(
      read.timeout(const Duration(seconds: 1)),
      throwsA(_failure(ApiFailureCategory.cancelled)),
    );
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();
    await cancelled;
    device.complete(const AppDeviceInfo());
  });

  test(
    'session epoch invalidates a late App response before parsing',
    () async {
      final pending = Completer<ApiHttpResponse>();
      final transport = _Transport((uri, index) => pending.future);
      final session = _Session();
      final read = AppPlaybackClient(
        _client(transport, sessionProvider: session),
      ).getPlayInfo(_bvid, _cid, buvid: _buvid);
      final cancelled = expectLater(
        read,
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      await Future<void>.delayed(Duration.zero);
      session.sessionEpoch++;
      pending.complete(_response(_data));
      await cancelled;
      expect(transport.attempts, hasLength(1));
    },
  );
}

BiliApiClient _client(
  _Transport transport, {
  Future<AppDeviceInfo> Function()? loadAppDevice,
  ApiSessionProvider? sessionProvider,
  DateTime Function()? clock,
}) {
  final api = BiliApiClient(
    transport: transport,
    loadAppDevice: loadAppDevice,
    sessionProvider: sessionProvider,
    clock: clock,
  );
  addTearDown(api.close);
  return api;
}

ApiHttpResponse _response(Object? data, {int code = 0, int status = 200}) =>
    ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );

Matcher _failure(ApiFailureCategory category) => isA<ApiFailure>().having(
  (failure) => failure.category,
  'category',
  category,
);

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

final class _Attempt {
  const _Attempt(this.uri, this.headers, this.timeout, this.cancellation);
  final Uri uri;
  final Map<String, String> headers;
  final Duration timeout;
  final ApiCancellation? cancellation;
}

final class _Transport implements ApiTransport {
  _Transport([this.handler]);
  final Future<ApiHttpResponse> Function(Uri uri, int index)? handler;
  final attempts = <_Attempt>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final index = attempts.length;
    attempts.add(_Attempt(uri, headers, timeout, cancellation));
    final handler = this.handler;
    return handler == null ? _response(_data) : handler(uri, index);
  }
}
