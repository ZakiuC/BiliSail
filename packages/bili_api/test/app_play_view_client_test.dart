import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _bvid = 'BV1q6ad6NEVK';
const _cid = '42328985110';
const _buvid = 'XY1234567890ABCDEF1234567890ABCDEF12345';

void main() {
  test(
    'PlayView parses high tiers, every audio format and safe metadata',
    () async {
      final transport = _GrpcTransport(_frame(_replyBytes()));
      final api = _api();
      final info = await AppPlayViewClient(api, transport: transport)
          .getPlayInfo(
            _bvid,
            _cid,
            qn: 127,
            unlimitedQualityTrial: true,
            buvid: _buvid,
            accessToken: 'app-token-fixture',
          );

      expect(info.dashVideo.map((track) => track.id), [126, 120]);
      expect(info.dashVideo.first.codecs, 'dvh1.05.06');
      expect(info.dashVideo[1].codecs, 'hev1.1.6.L120.B0');
      expect(info.dashVideo[1].bandwidth, 5000);
      expect(info.dashAudio.map((track) => track.id), [
        30280,
        30232,
        30250,
        30251,
      ]);
      expect(info.dashAudio.map((track) => track.codecs), [
        'mp4a.40.2',
        'mp4a.40.29',
        'ec-3',
        'fLaC',
      ]);
      expect(info.acceptQuality, [126, 120]);
      expect(info.duration, const Duration(milliseconds: 60000));

      final request = transport.requests.single;
      expect(
        request.uri.path,
        '/bilibili.app.playerunite.v1.Player/PlayViewUnite',
      );
      expect(request.headers['authorization'], 'identify_v1 app-token-fixture');
      expect(request.headers['buvid'], _buvid);
      expect(request.headers.containsKey('cookie'), isFalse);
      expect(request.headers['content-type'], 'application/grpc');
      expect(request.body[0], 0);
      expect(
        ByteData.sublistView(request.body, 1, 5).getUint32(0, Endian.big),
        request.body.length - 5,
      );
    },
  );

  test(
    'profile switches the announced client in metadata and User-Agent',
    () async {
      Future<Map<String, String>> headersFor(AppPlayViewProfile profile) async {
        final transport = _GrpcTransport(_frame(_replyBytes()));
        await AppPlayViewClient(
          _api(),
          transport: transport,
          profile: profile,
        ).getPlayInfo(_bvid, _cid, buvid: _buvid);
        return transport.requests.single.headers;
      }

      final hd = await headersFor(AppPlayViewProfile.androidHd);
      final hdMetadata = latin1.decode(
        base64Decode(hd['x-bili-metadata-bin']!),
      );
      expect(hdMetadata, contains('android_hd'));
      expect(hd['user-agent'], contains('mobi_app/android_hd build/2001100'));

      final phone = await headersFor(AppPlayViewProfile.phone);
      final phoneMetadata = latin1.decode(
        base64Decode(phone['x-bili-metadata-bin']!),
      );
      final phoneDevice = latin1.decode(
        base64Decode(phone['x-bili-device-bin']!),
      );
      expect(phoneMetadata, isNot(contains('android_hd')));
      expect(phoneMetadata, contains('android'));
      expect(phoneDevice, contains('phone'));
      expect(phone['user-agent'], contains('mobi_app/android build/9190000'));
      expect(phone['content-type'], 'application/grpc');
    },
  );

  test('compressed gRPC messages decode within the size cap', () async {
    final compressed = gzip.encode(_replyBytes());
    final body = Uint8List(compressed.length + 5)
      ..[0] = 1
      ..buffer.asByteData(1, 4).setUint32(0, compressed.length, Endian.big)
      ..setAll(5, compressed);
    final api = _api();
    final info = await AppPlayViewClient(
      api,
      transport: _GrpcTransport(body),
    ).getPlayInfo(_bvid, _cid, buvid: _buvid);
    expect(info.dashVideo, hasLength(2));
  });

  test('grpc status codes never become a successful empty reply', () async {
    for (final (status, category) in [
      (7, ApiFailureCategory.permission),
      (16, ApiFailureCategory.authentication),
      (4, ApiFailureCategory.timeout),
      (14, ApiFailureCategory.unavailable),
    ]) {
      final api = _api();
      await expectLater(
        AppPlayViewClient(
          api,
          transport: _GrpcTransport(_frame(_replyBytes()), grpcStatus: status),
        ).getPlayInfo(_bvid, _cid, buvid: _buvid),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            category,
          ),
        ),
      );
    }
  });

  test(
    'a reply without VodInfo is unavailable, not a silent success',
    () async {
      final api = _api();
      await expectLater(
        AppPlayViewClient(
          api,
          transport: _GrpcTransport(Uint8List.fromList([0, 0, 0, 0, 0])),
        ).getPlayInfo(_bvid, _cid, buvid: _buvid),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.unavailable,
          ),
        ),
      );
    },
  );

  test('invalid targets are rejected before any transport call', () async {
    final transport = _GrpcTransport(_frame(_replyBytes()));
    final api = _api();
    await expectLater(
      AppPlayViewClient(
        api,
        transport: transport,
      ).getPlayInfo('not-a-bvid', _cid, buvid: _buvid),
      throwsArgumentError,
    );
    expect(transport.requests, isEmpty);
  });
}

BiliApiClient _api() {
  final api = BiliApiClient(
    loadAppDevice: () async => const AppDeviceInfo(model: 'Pixel 9'),
  );
  addTearDown(api.close);
  return api;
}

final class _Attempt {
  const _Attempt(this.uri, this.headers, this.body);
  final Uri uri;
  final Map<String, String> headers;
  final Uint8List body;
}

final class _GrpcTransport implements ApiGrpcTransport {
  _GrpcTransport(this.body, {this.grpcStatus = 0});
  final Uint8List body;
  final int grpcStatus;
  final requests = <_Attempt>[];

  @override
  Future<ApiHttpResponse> postGrpc(
    Uri uri, {
    required Uint8List body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(_Attempt(uri, headers, body));
    return ApiHttpResponse(200, this.body, {
      'grpc-status': ['$grpcStatus'],
    });
  }
}

Uint8List _replyBytes() => (_W()..message(1, _vod())).bytes();

Uint8List _frame(Uint8List message) {
  final frame = Uint8List(message.length + 5);
  frame.buffer.asByteData(1, 4).setUint32(0, message.length, Endian.big);
  frame.setAll(5, message);
  return frame;
}

List<int> _vod() =>
    (_W()
          ..varint(3, 60000)
          ..message(5, _stream(126, 9000, 12))
          ..message(5, _stream(120, 5000, 12))
          ..message(6, _dashItem(30280, 192000))
          ..message(6, _dashItem(30232, 132000))
          ..message(7, _dolby())
          ..message(9, _lossless()))
        .bytes();

List<int> _stream(int quality, int bandwidth, int codecId) =>
    (_W()
          ..message(1, _streamInfo(quality))
          ..message(2, _dashVideo(bandwidth, codecId)))
        .bytes();

List<int> _streamInfo(int quality) => (_W()..varint(1, quality)).bytes();

List<int> _dolby() => (_W()..message(2, _dashItem(30250, 640000))).bytes();

List<int> _lossless() => (_W()..message(2, _dashItem(30251, 800000))).bytes();

List<int> _dashVideo(int bandwidth, int codecId) =>
    (_W()
          ..string(1, 'https://upos-sz-mirror.bilivideo.com/v-$bandwidth.m4s')
          ..string(2, 'https://backup.example/v-$bandwidth.m4s')
          ..varint(3, bandwidth)
          ..varint(4, codecId))
        .bytes();

List<int> _dashItem(int id, int bandwidth) =>
    (_W()
          ..varint(1, id)
          ..string(2, 'https://upos-sz-mirror.bilivideo.com/a-$id.m4s')
          ..varint(4, bandwidth))
        .bytes();

final class _W {
  final _builder = BytesBuilder(copy: false);

  Uint8List bytes() => _builder.toBytes();

  void varint(int field, int value) {
    if (value == 0) return;
    _put(field << 3);
    _put(value);
  }

  void string(int field, String value) => message(field, utf8.encode(value));

  void message(int field, List<int> value) {
    _put((field << 3) | 2);
    _put(value.length);
    _builder.add(value);
  }

  void _put(int value) {
    var rest = value;
    while (rest >= 0x80) {
      _builder.addByte((rest & 0x7f) | 0x80);
      rest >>= 7;
    }
    _builder.addByte(rest);
  }
}
