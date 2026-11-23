import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/features/playback/data/app_play_info_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _identity = (
  buvid: 'XY1234567890ABCDEF1234567890ABCDEF12345',
  accessToken: 'app-token-fixture',
  revision: 0,
);

void main() {
  test(
    'only a current App authentication failure invalidates identity',
    () async {
      final transport = _Transport(
        (_) async => _response({'code': -101, 'message': 'expired'}),
      );
      final requests = ApiRequests();
      final api = _api(transport, requests);
      var invalidations = 0;
      final source = _source(
        api,
        requests,
        invalidate: () async => invalidations++,
      );

      await expectLater(
        source.resolve(
          bvid: 'BV1q6ad6NEVK',
          cid: '42328985110',
          quality: 127,
          language: '',
          productionType: 0,
          unlimitedQualityTrial: false,
          context: const ApiRequestContext(sessionEpoch: 0),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
      expect(invalidations, 1);
    },
  );

  test('network failure never invalidates the App identity', () async {
    final transport = _Transport(
      (_) async =>
          throw const ApiFailure(ApiFailureCategory.network, 'transport'),
    );
    final requests = ApiRequests();
    final api = _api(transport, requests);
    var invalidations = 0;
    final source = _source(
      api,
      requests,
      invalidate: () async => invalidations++,
    );
    await expectLater(
      source.resolve(
        bvid: 'BV1q6ad6NEVK',
        cid: '42328985110',
        quality: 127,
        language: '',
        productionType: 0,
        unlimitedQualityTrial: false,
        context: const ApiRequestContext(sessionEpoch: 0),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(invalidations, 0);
  });

  test(
    'an identity change during the App request cancels the result',
    () async {
      final started = Completer<void>();
      final finish = Completer<void>();
      final transport = _Transport((_) async {
        started.complete();
        await finish.future;
        return _response({'code': 0, 'data': _data});
      });
      final requests = ApiRequests();
      final api = _api(transport, requests);
      var revision = 0;
      var invalidations = 0;
      final source = _source(
        api,
        requests,
        revision: () => revision,
        invalidate: () async => invalidations++,
      );
      final result = source.resolve(
        bvid: 'BV1q6ad6NEVK',
        cid: '42328985110',
        quality: 127,
        language: '',
        productionType: 0,
        unlimitedQualityTrial: false,
        context: const ApiRequestContext(sessionEpoch: 0),
      );
      await started.future;
      revision = 1;
      finish.complete();

      await expectLater(
        result,
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      expect(invalidations, 0);
    },
  );
}

AppPlayInfoSource _source(
  BiliApiClient api,
  ApiRequests requests, {
  int Function() revision = _zero,
  required Future<void> Function() invalidate,
}) => AppPlayInfoSource(
  api,
  requests,
  loadIdentity: () async => _identity,
  identityRevision: revision,
  invalidateIdentity: invalidate,
);

int _zero() => 0;

BiliApiClient _api(_Transport transport, ApiRequests requests) {
  final api = BiliApiClient(
    transport: transport,
    sessionProvider: requests,
    loadAppDevice: () async => const AppDeviceInfo(),
  );
  addTearDown(api.close);
  return api;
}

final class _Transport implements ApiTransport {
  const _Transport(this.handler);
  final Future<ApiHttpResponse> Function(Uri uri) handler;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => handler(uri);
}

ApiHttpResponse _response(Map<String, Object?> value) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode(value))),
  const {},
);

const _data = <String, Object?>{
  'accept_quality': [127],
  'timelength': 60000,
  'dash': {
    'duration': 60,
    'video': [
      {
        'id': 127,
        'base_url': 'https://cdn.example/video.m4s',
        'codecs': 'avc1.640034',
      },
    ],
    'audio': [
      {
        'id': 30280,
        'base_url': 'https://cdn.example/audio.m4s',
        'codecs': 'mp4a.40.2',
      },
    ],
  },
};
