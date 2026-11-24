import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../api_client.dart';
import '../app_profile.dart';
import '../models.dart';
import '../transport.dart';

/// Client identity carried by the binary metadata headers.
///
/// The server clamps the returned DASH ladder to what it believes the client
/// supports, so a legacy HD profile can be limited to 1080P even when the video
/// and account have 4K/Dolby tiers. Profiles only change announced device facts.
final class AppPlayViewProfile {
  const AppPlayViewProfile({
    required this.mobiApp,
    required this.device,
    required this.build,
    required this.versionName,
  });

  /// Current default: HD (tablet) profile used by the rest of the App channel.
  static const androidHd = AppPlayViewProfile(
    mobiApp: 'android_hd',
    device: 'android',
    build: 2001100,
    versionName: '2.0.1',
  );

  /// Phone profile, for playurl reads that the HD profile caps at 1080P.
  static const phone = AppPlayViewProfile(
    mobiApp: 'android',
    device: 'phone',
    build: 9000100,
    versionName: '9.0.1',
  );

  final String mobiApp;
  final String device;
  final int build;
  final String versionName;

  String get key => '$mobiApp/$build';
}

/// Official App PlayViewUnite playback over a single uncompressed gRPC frame.
/// Web cookies are never read or copied into this App-only channel.
final class AppPlayViewClient {
  AppPlayViewClient(
    this.api, {
    ApiGrpcTransport? transport,
    this.profile = AppPlayViewProfile.androidHd,
  }) : _transport = transport ?? DioApiTransport(),
       _ownsTransport = transport == null;

  final AppPlayViewProfile profile;

  final BiliApiClient api;
  final ApiGrpcTransport _transport;
  final bool _ownsTransport;
  final String _fawkesSession = _randomHex(4);

  static const _endpoint = 'app_playviewunite';
  static const _maxMessageBytes = 4 * 1024 * 1024;
  static final _uri = Uri.https(
    'app.bilibili.com',
    '/bilibili.app.playerunite.v1.Player/PlayViewUnite',
  );

  Future<ApiPlayInfo> getPlayInfo(
    String bvid,
    String cid, {
    int qn = 80,
    String language = '',
    int productionType = 0,
    bool unlimitedQualityTrial = false,
    required String buvid,
    String? accessToken,
    AppDeviceInfo? deviceInfo,
    ApiRequestContext? context,
  }) async {
    final numericCid = _validateTarget(
      bvid,
      cid,
      qn,
      language,
      productionType,
      buvid,
      accessToken,
    );
    final active = api.boundedReadContext(context);
    final epoch = _contextState().epoch;
    final deadline = active.deadline;
    if (deadline == null) {
      throw const ApiFailure(ApiFailureCategory.timeout, _endpoint);
    }

    void check() {
      final current = _contextState();
      if (active.cancellation?.isCancelled == true ||
          (epoch != null && current.epoch != epoch) ||
          (active.sessionEpoch != null && active.sessionEpoch != epoch)) {
        throw const ApiFailure(ApiFailureCategory.cancelled, _endpoint);
      }
      if (!deadline.isAfter(current.now)) {
        throw const ApiFailure(ApiFailureCategory.timeout, _endpoint);
      }
    }

    check();
    final device = deviceInfo ?? await api.appDeviceInfo(context: active);
    check();
    final request = _playViewRequest(
      bvid: bvid,
      cid: numericCid,
      qn: qn,
      language: language,
      unlimitedQualityTrial: unlimitedQualityTrial,
    );
    final response = await _post(
      request,
      buvid: buvid,
      accessToken: accessToken,
      device: device,
      active: active,
      check: check,
    );
    check();
    final message = await _decodeGrpcResponse(response);
    check();
    final info = _parseReply(
      message,
      requestedLanguage: language,
      requestedProductionType: productionType,
    );
    check();
    return info;
  }

  /// Closes only the transport created by this client, never an injected one.
  void close() {
    final transport = _transport;
    if (_ownsTransport && transport is DioApiTransport) transport.close();
  }

  ({int? epoch, DateTime now}) _contextState() {
    // This exposes the injected clock and epoch without widening BiliApiClient.
    final current = api.boundedReadContext(null);
    final deadline = current.deadline;
    if (deadline == null) {
      throw const ApiFailure(ApiFailureCategory.timeout, _endpoint);
    }
    return (epoch: current.sessionEpoch, now: deadline.subtract(api.timeout));
  }

  Future<ApiHttpResponse> _post(
    Uint8List request, {
    required String buvid,
    required String? accessToken,
    required AppDeviceInfo device,
    required ApiRequestContext active,
    required void Function() check,
  }) async {
    final deadline = active.deadline;
    if (deadline == null) {
      throw const ApiFailure(ApiFailureCategory.timeout, _endpoint);
    }
    final remaining = deadline.difference(_contextState().now);
    if (remaining <= Duration.zero) {
      throw const ApiFailure(ApiFailureCategory.timeout, _endpoint);
    }
    final cancellation = active.cancellation;
    try {
      return await Future.any<ApiHttpResponse>([
        _transport.postGrpc(
          _uri,
          body: _grpcFrame(request),
          headers: _metadata(
            buvid: buvid,
            accessToken: accessToken,
            device: device,
          ),
          timeout: remaining,
          cancellation: cancellation,
        ),
        if (cancellation != null)
          cancellation.whenCancelled.then<ApiHttpResponse>(
            (_) =>
                throw const ApiFailure(ApiFailureCategory.cancelled, _endpoint),
          ),
      ]).timeout(
        remaining,
        onTimeout: () =>
            throw const ApiFailure(ApiFailureCategory.timeout, _endpoint),
      );
    } on TimeoutException {
      throw const ApiFailure(ApiFailureCategory.timeout, _endpoint);
    } on ApiFailure catch (error) {
      check();
      if (error.endpointId == 'transport') {
        throw ApiFailure(error.category, _endpoint);
      }
      rethrow;
    }
  }

  Map<String, String> _metadata({
    required String buvid,
    required String? accessToken,
    required AppDeviceInfo device,
  }) {
    final token = accessToken == null || accessToken.isEmpty
        ? null
        : accessToken;
    final deviceMessage = _WireWriter()
      ..varintField(1, 5)
      ..varintField(2, profile.build)
      ..stringField(3, buvid)
      ..stringField(4, profile.mobiApp)
      ..stringField(5, 'android')
      ..stringField(6, profile.device)
      ..stringField(7, 'master')
      ..stringField(8, 'android')
      ..stringField(9, device.model)
      ..stringField(10, device.osVersion)
      ..stringField(13, profile.versionName);
    final metadata = _WireWriter()
      ..stringField(1, token ?? '')
      ..stringField(2, profile.mobiApp)
      ..stringField(3, profile.device)
      ..varintField(4, profile.build)
      ..stringField(5, 'master')
      ..stringField(6, buvid)
      ..stringField(7, 'android');
    final networkType = switch (device.network) {
      'wifi' => 1,
      'mobile' => 2,
      _ => 0,
    };
    final network = _WireWriter()..varintField(1, networkType);
    final localeIds = _localeIds();
    final locale = _WireWriter()
      ..messageField(1, localeIds)
      ..messageField(2, localeIds)
      ..stringField(4, 'Asia/Shanghai');
    final fawkes = _WireWriter()
      ..stringField(1, profile.mobiApp)
      ..stringField(2, 'prod')
      ..stringField(3, _fawkesSession);
    String binary(_WireWriter writer) => base64Encode(writer.bytes);
    return <String, String>{
      'content-type': 'application/grpc',
      'grpc-encoding': 'identity',
      'grpc-accept-encoding': 'gzip,identity',
      'gzip-accept-encoding': 'gzip,identity',
      'user-agent': _userAgent(device),
      'buvid': buvid,
      'x-bili-trace-id': '${_randomHex(16)}:${_randomHex(8)}:0:0',
      'x-bili-exps-bin': '',
      'x-bili-aurora-zone': '',
      'x-bili-gaia-vtoken': '',
      'bili-http-engine': 'cronet',
      if (token != null) 'authorization': 'identify_v1 $token',
      'x-bili-device-bin': binary(deviceMessage),
      'x-bili-metadata-bin': binary(metadata),
      'x-bili-network-bin': binary(network),
      'x-bili-locale-bin': binary(locale),
      'x-bili-fawkes-req-bin': binary(fawkes),
    };
  }

  /// Declares the same client the metadata headers and User-Agent describe.
  String _userAgent(AppDeviceInfo device) =>
      'Mozilla/5.0 BiliDroid/${profile.versionName} (bbcallen@gmail.com) os/android '
      'model/${device.model} mobi_app/${profile.mobiApp} build/${profile.build} '
      'channel/master innerVer/${profile.build} osVer/${device.osVersion} '
      'network/${switch (device.network) {
        'mobile' => '1',
        'wifi' => '2',
        _ => '0',
      }}';

  static Uint8List _localeIds() =>
      (_WireWriter()
            ..stringField(1, 'zh')
            ..stringField(2, 'Hans')
            ..stringField(3, 'CN'))
          .bytes;

  static Uint8List _playViewRequest({
    required String bvid,
    required int cid,
    required int qn,
    required String language,
    required bool unlimitedQualityTrial,
  }) {
    final vod = _WireWriter()
      ..varintField(2, cid)
      ..varintField(3, qn)
      ..varintField(5, 4048)
      ..varintField(7, 2)
      ..varintField(8, 1)
      ..varintField(10, 1)
      ..varintField(11, unlimitedQualityTrial ? 1 : 0)
      ..stringField(15, language);
    // UGC identity is bvid + cid. aid and an unmapped productionType are absent.
    return (_WireWriter()
          ..messageField(1, vod.bytes)
          ..stringField(5, bvid))
        .bytes;
  }

  static int _validateTarget(
    String bvid,
    String cid,
    int qn,
    String language,
    int productionType,
    String buvid,
    String? accessToken,
  ) {
    final numericCid = int.tryParse(cid);
    if (!RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(bvid) ||
        numericCid == null ||
        numericCid <= 0 ||
        !RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(cid) ||
        qn <= 0 ||
        !RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(buvid) ||
        !const [0, 1, 2].contains(productionType) ||
        (productionType == 0) != language.isEmpty ||
        language.length > 32 ||
        (language.isNotEmpty &&
            !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(language)) ||
        (accessToken != null &&
            (accessToken.length > 1024 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(accessToken)))) {
      throw ArgumentError('Invalid App PlayViewUnite target');
    }
    return numericCid;
  }
}

Uint8List _grpcFrame(Uint8List message) {
  final frame = Uint8List(message.length + 5);
  frame.buffer.asByteData(1, 4).setUint32(0, message.length, Endian.big);
  frame.setAll(5, message);
  return frame;
}

Future<Uint8List> _decodeGrpcResponse(ApiHttpResponse response) async {
  const endpoint = AppPlayViewClient._endpoint;
  final httpStatus = response.statusCode;
  if (httpStatus < 200 || httpStatus >= 300) {
    throw ApiFailure(
      switch (httpStatus) {
        401 || 403 => ApiFailureCategory.authentication,
        404 => ApiFailureCategory.notFound,
        429 => ApiFailureCategory.rateLimited,
        _ => ApiFailureCategory.http,
      },
      endpoint,
      httpStatus: httpStatus,
    );
  }
  final statusValues = response.header('grpc-status');
  final status = statusValues.length == 1
      ? int.tryParse(statusValues.single.trim())
      : null;
  if (status == null) {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  if (status != 0) {
    throw ApiFailure(_grpcFailureCategory(status), endpoint);
  }
  final body = response.body;
  if (body.length < 5 || body.length > AppPlayViewClient._maxMessageBytes) {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  final flag = body[0];
  if (flag != 0 && flag != 1) {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  final length = ByteData.sublistView(body, 1, 5).getUint32(0, Endian.big);
  if (length != body.length - 5) {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
  final payload = Uint8List.sublistView(body, 5);
  if (flag == 0) return payload;
  try {
    final decoded = BytesBuilder(copy: false);
    await for (final chunk in gzip.decoder.bind(
      Stream<List<int>>.value(payload),
    )) {
      if (decoded.length + chunk.length > AppPlayViewClient._maxMessageBytes) {
        throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
      }
      decoded.add(chunk);
    }
    return decoded.takeBytes();
  } on ApiFailure {
    rethrow;
  } on Exception {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
}

ApiFailureCategory _grpcFailureCategory(int status) => switch (status) {
  1 => ApiFailureCategory.cancelled,
  4 => ApiFailureCategory.timeout,
  5 => ApiFailureCategory.notFound,
  7 => ApiFailureCategory.permission,
  8 => ApiFailureCategory.rateLimited,
  14 => ApiFailureCategory.unavailable,
  15 => ApiFailureCategory.protocol,
  16 => ApiFailureCategory.authentication,
  _ => ApiFailureCategory.unavailable,
};

ApiPlayInfo _parseReply(
  Uint8List bytes, {
  required String requestedLanguage,
  required int requestedProductionType,
}) {
  const endpoint = AppPlayViewClient._endpoint;
  try {
    Uint8List? vodBytes;
    final reply = _WireReader(bytes);
    while (!reply.done) {
      final key = reply.key();
      if (key.$1 == 1 && key.$2 == 2) {
        vodBytes = reply.byteString();
      } else {
        reply.skip(key.$2);
      }
    }
    if (vodBytes == null) {
      throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
    }
    return _parseVodInfo(
      vodBytes,
      requestedLanguage: requestedLanguage,
      requestedProductionType: requestedProductionType,
    );
  } on ApiFailure {
    rethrow;
  } on FormatException {
    throw const ApiFailure(ApiFailureCategory.protocol, endpoint);
  }
}

ApiPlayInfo _parseVodInfo(
  Uint8List bytes, {
  required String requestedLanguage,
  required int requestedProductionType,
}) {
  const endpoint = AppPlayViewClient._endpoint;
  var timeLength = 0;
  var currentLanguage = '';
  final streams = <Uint8List>[];
  final audioBytes = <Uint8List>[];
  final specialAudioBytes = <Uint8List>[];
  final vod = _WireReader(bytes);
  while (!vod.done) {
    final key = vod.key();
    final field = key.$1;
    final wire = key.$2;
    if (field == 3 && wire == 0) {
      timeLength = vod.varint();
    } else if (field == 5 && wire == 2) {
      streams.add(vod.byteString());
    } else if (field == 6 && wire == 2) {
      audioBytes.add(vod.byteString());
    } else if (field == 7 && wire == 2) {
      final dolby = _WireReader(vod.byteString());
      while (!dolby.done) {
        final nested = dolby.key();
        if (nested.$1 == 2 && nested.$2 == 2) {
          specialAudioBytes.add(dolby.byteString());
        } else {
          dolby.skip(nested.$2);
        }
      }
    } else if (field == 9 && wire == 2) {
      final lossless = _WireReader(vod.byteString());
      while (!lossless.done) {
        final nested = lossless.key();
        if (nested.$1 == 2 && nested.$2 == 2) {
          specialAudioBytes.add(lossless.byteString());
        } else {
          lossless.skip(nested.$2);
        }
      }
    } else if (field == 13 && wire == 2) {
      currentLanguage = vod.string();
    } else {
      vod.skip(wire);
    }
  }

  final videos = <ApiMediaTrack>[];
  final qualities = <int>{};
  for (final streamBytes in streams) {
    var quality = 0;
    final dashVideos = <Uint8List>[];
    final stream = _WireReader(streamBytes);
    while (!stream.done) {
      final key = stream.key();
      if (key.$1 == 1 && key.$2 == 2) {
        final info = _WireReader(stream.byteString());
        while (!info.done) {
          final nested = info.key();
          if (nested.$1 == 1 && nested.$2 == 0) {
            quality = info.varint();
          } else {
            // need_vip (6) is entitlement metadata, not a track filter.
            info.skip(nested.$2);
          }
        }
      } else if (key.$1 == 2 && key.$2 == 2) {
        dashVideos.add(stream.byteString());
      } else if (key.$1 == 4 && key.$2 == 2) {
        final multi = _WireReader(stream.byteString());
        while (!multi.done) {
          final nested = multi.key();
          if (nested.$1 == 1 && nested.$2 == 2) {
            dashVideos.add(multi.byteString());
          } else {
            multi.skip(nested.$2);
          }
        }
      } else {
        stream.skip(key.$2);
      }
    }
    for (final dash in dashVideos) {
      if (quality <= 0) throw const FormatException('Missing stream quality');
      videos.add(_videoTrack(dash, quality));
      qualities.add(quality);
    }
  }
  if (videos.isEmpty) {
    throw const ApiFailure(ApiFailureCategory.unavailable, endpoint);
  }
  final audios = <ApiMediaTrack>[
    for (final audio in audioBytes) _audioTrack(audio),
    for (final audio in specialAudioBytes) _audioTrack(audio),
  ];
  return ApiPlayInfo(
    duration: Duration(milliseconds: timeLength),
    dashVideo: List<ApiMediaTrack>.unmodifiable(videos),
    dashAudio: List<ApiMediaTrack>.unmodifiable(audios),
    acceptQuality: List<int>.unmodifiable(qualities),
    currentLanguage: currentLanguage,
    productionType: currentLanguage == requestedLanguage
        ? requestedProductionType
        : 0,
  );
}

ApiMediaTrack _videoTrack(Uint8List bytes, int quality) {
  var baseUrl = '';
  var bandwidth = 0;
  var codecId = 0;
  final backups = <Uri>[];
  final dash = _WireReader(bytes);
  while (!dash.done) {
    final key = dash.key();
    if (key.$1 == 1 && key.$2 == 2) {
      baseUrl = dash.string();
    } else if (key.$1 == 2 && key.$2 == 2) {
      final url = _mediaUri(dash.string());
      if (url != null) backups.add(url);
    } else if (key.$1 == 3 && key.$2 == 0) {
      bandwidth = dash.varint();
    } else if (key.$1 == 4 && key.$2 == 0) {
      codecId = dash.varint();
    } else {
      dash.skip(key.$2);
    }
  }
  final url = _mediaUri(baseUrl);
  if (url == null) throw const FormatException('Invalid video URL');
  final codecs = quality == 126
      ? 'dvh1.05.06'
      : switch (codecId) {
          7 => 'avc1.640028',
          12 => 'hev1.1.6.L120.B0',
          13 => 'av01.0.08M.08',
          _ => '',
        };
  return ApiMediaTrack(
    id: quality,
    url: url,
    backupUrls: List<Uri>.unmodifiable(backups),
    bandwidth: bandwidth,
    mimeType: 'video/mp4',
    codecs: codecs,
  );
}

ApiMediaTrack _audioTrack(Uint8List bytes) {
  var id = 0;
  var baseUrl = '';
  var bandwidth = 0;
  final backups = <Uri>[];
  final audio = _WireReader(bytes);
  while (!audio.done) {
    final key = audio.key();
    if (key.$1 == 1 && key.$2 == 0) {
      id = audio.varint();
    } else if (key.$1 == 2 && key.$2 == 2) {
      baseUrl = audio.string();
    } else if (key.$1 == 3 && key.$2 == 2) {
      final url = _mediaUri(audio.string());
      if (url != null) backups.add(url);
    } else if (key.$1 == 4 && key.$2 == 0) {
      bandwidth = audio.varint();
    } else {
      audio.skip(key.$2);
    }
  }
  final url = _mediaUri(baseUrl);
  if (id <= 0 || url == null) {
    throw const FormatException('Invalid audio track');
  }
  return ApiMediaTrack(
    id: id,
    url: url,
    backupUrls: List<Uri>.unmodifiable(backups),
    bandwidth: bandwidth,
    mimeType: 'audio/mp4',
    codecs: switch (id) {
      30216 => 'mp4a.40.5',
      30232 => 'mp4a.40.29',
      30280 => 'mp4a.40.2',
      30251 => 'fLaC',
      30250 || 30255 => 'ec-3',
      _ => '',
    },
  );
}

Uri? _mediaUri(String value) {
  if (value.isEmpty || value.length > 8192) return null;
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

String _randomHex(int byteCount) {
  final random = Random.secure();
  return List<String>.generate(
    byteCount,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

final class _WireWriter {
  final _builder = BytesBuilder(copy: false);

  Uint8List get bytes => _builder.toBytes();

  void varintField(int field, int value) {
    if (value == 0) return;
    _varint(field << 3);
    _varint(value);
  }

  void stringField(int field, String value) {
    if (value.isEmpty) return;
    messageField(field, utf8.encode(value));
  }

  void messageField(int field, List<int> value) {
    _varint((field << 3) | 2);
    _varint(value.length);
    _builder.add(value);
  }

  void _varint(int value) {
    var remaining = value;
    while (remaining >= 0x80) {
      _builder.addByte((remaining & 0x7f) | 0x80);
      remaining >>= 7;
    }
    _builder.addByte(remaining);
  }
}

final class _WireReader {
  _WireReader(this._bytes) : _end = _bytes.length;

  final Uint8List _bytes;
  final int _end;
  int _offset = 0;
  static final _maxInt64 = BigInt.parse('9223372036854775807');

  bool get done => _offset == _end;

  (int, int) key() {
    final value = varint();
    final field = value >> 3;
    final wire = value & 7;
    if (field == 0) throw const FormatException('Invalid field');
    return (field, wire);
  }

  int varint() {
    final value = _unsignedVarint();
    if (value > _maxInt64) throw const FormatException('Integer overflow');
    return value.toInt();
  }

  BigInt _unsignedVarint() {
    var value = BigInt.zero;
    for (var index = 0; index < 10; index++) {
      if (_offset >= _end) throw const FormatException('Truncated varint');
      final byte = _bytes[_offset++];
      if (index == 9 && byte > 1) {
        throw const FormatException('Varint overflow');
      }
      value |= BigInt.from(byte & 0x7f) << (index * 7);
      if (byte < 0x80) return value;
    }
    throw const FormatException('Invalid varint');
  }

  Uint8List byteString() {
    final length = varint();
    if (length > _end - _offset) {
      throw const FormatException('Truncated bytes');
    }
    final result = Uint8List.sublistView(_bytes, _offset, _offset + length);
    _offset += length;
    return result;
  }

  String string() => utf8.decode(byteString());

  void skip(int wire) {
    switch (wire) {
      case 0:
        _unsignedVarint();
      case 1:
        _advance(8);
      case 2:
        final length = varint();
        _advance(length);
      case 5:
        _advance(4);
      default:
        throw const FormatException('Unsupported wire type');
    }
  }

  void _advance(int length) {
    if (length > _end - _offset) {
      throw const FormatException('Truncated field');
    }
    _offset += length;
  }
}
