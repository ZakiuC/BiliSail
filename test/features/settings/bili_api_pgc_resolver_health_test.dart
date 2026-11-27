import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/features/settings/data/bili_api_pgc_resolver_health.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeTransport implements ApiTransport {
  _FakeTransport(this.reply);

  final FutureOr<ApiHttpResponse> Function(Uri uri) reply;
  final uris = <Uri>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    uris.add(uri);
    return Future<ApiHttpResponse>.sync(() => reply(uri));
  }
}

ApiHttpResponse _json(Object? value, {int status = 200}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode(value))),
  const {},
);

Map<String, Object?> _season(Object? episodes) => {
  'season_id': 42,
  'title': 'Verified season',
  'episodes':
      episodes ??
      [
        {
          'id': 9,
          'aid': 99,
          'cid': 999,
          'bvid': 'BV1ab411c7mD',
          'title': '1',
          'long_title': 'Verified episode',
          'status': 2,
          'duration': 123456,
        },
      ],
  'section': const [],
  'seasons': const [],
};

Map<String, Object?> _play() => {
  'timelength': 123456,
  'is_preview': 0,
  'dash': {
    'duration': 123.456,
    'video': [
      {
        'id': 64,
        'base_url': 'https://upos-sz-mirror.bilivideo.com/video.m4s',
        'bandwidth': 2_000_000,
        'mime_type': 'video/mp4',
        'codecs': 'avc1.640028',
      },
    ],
    'audio': [
      {
        'id': 30232,
        'base_url': 'https://upos-sz-mirror.bilivideo.com/audio.m4s',
        'bandwidth': 128000,
        'mime_type': 'audio/mp4',
        'codecs': 'mp4a.40.2',
      },
    ],
  },
};

bool _isPlay(Uri uri) => uri.path.contains('playurl');

void main() {
  test(
    'reports usable when season and playurl both answer anonymously',
    () async {
      final transport = _FakeTransport(
        (uri) => _isPlay(uri)
            ? _json({'code': 0, 'result': _play()})
            : _json({'code': 0, 'result': _season(null)}),
      );
      final health = await BiliApiPgcResolverHealth(transport: () => transport)
          .check(baseUrl: 'https://resolver.example.com', region: 'hk');

      expect(health.usable, isTrue);
      expect(health.failure, isNull);
      expect(health.summary, contains('可用'));
      // Anonymous headers only, and the checked area is forwarded.
      expect(transport.uris, isNotEmpty);
      expect(
        transport.uris.every((uri) => uri.host == 'resolver.example.com'),
        isTrue,
      );
      expect(transport.uris.last.queryParameters['area'], 'hk');
    },
  );

  test('reports detail-only when playurl is refused', () async {
    final transport = _FakeTransport(
      (uri) => _isPlay(uri)
          ? _json({'code': -10403, 'message': 'area limited'})
          : _json({'code': 0, 'result': _season(null)}),
    );
    final health = await BiliApiPgcResolverHealth(transport: () => transport)
        .check(baseUrl: 'https://resolver.example.com', region: 'tw');

    expect(health.seasonReady, isTrue);
    expect(health.playbackReady, isFalse);
    expect(health.partial, isTrue);
    expect(health.failure, '服务器返回地区拒绝');
    expect(health.summary, startsWith('仅详情可用'));
  });

  test('reports an address that demands credentials', () async {
    final transport = _FakeTransport(
      (uri) => _isPlay(uri)
          ? _json({'code': 401, 'message': 'access_key required'})
          : _json({'code': 0, 'result': _season(null)}),
    );
    final health = await BiliApiPgcResolverHealth(transport: () => transport)
        .check(baseUrl: 'https://resolver.example.com', region: 'hk');

    expect(health.usable, isFalse);
    expect(health.failure, '服务器要求账号凭据');
  });

  test('falls back to the next sample when an episode is gone', () async {
    var seasonCalls = 0;
    final transport = _FakeTransport((uri) {
      if (_isPlay(uri)) return _json({'code': 0, 'result': _play()});
      seasonCalls++;
      return seasonCalls == 1
          ? _json({'code': 0, 'result': _season(const [])})
          : _json({'code': 0, 'result': _season(null)});
    });
    final health = await BiliApiPgcResolverHealth(transport: () => transport)
        .check(baseUrl: 'https://resolver.example.com', region: 'hk');

    expect(seasonCalls, 2);
    expect(health.usable, isTrue);
  });

  test(
    'rejects malformed addresses and unknown regions without requests',
    () async {
      var calls = 0;
      final checker = BiliApiPgcResolverHealth(
        transport: () => _FakeTransport((uri) {
          calls++;
          return _json({'code': 0});
        }),
      );

      final invalid = await checker.check(baseUrl: 'not a url', region: 'hk');
      expect(invalid.failure, '地址无效');
      expect(invalid.usable, isFalse);

      final unknown = await checker.check(
        baseUrl: 'https://resolver.example.com',
        region: 'mars',
      );
      expect(unknown.failure, '未知地区');
      expect(calls, 0);
    },
  );

  test('reports network failures instead of claiming success', () async {
    final health = await BiliApiPgcResolverHealth(
      transport: () => _FakeTransport((uri) => throw const SocketStub()),
    ).check(baseUrl: 'https://resolver.example.com', region: 'hk');

    expect(health.usable, isFalse);
    expect(health.seasonReady, isFalse);
    expect(health.failure, '网络不可达');
  });
}

final class SocketStub implements Exception {
  const SocketStub();
}
