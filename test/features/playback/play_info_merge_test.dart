import 'package:bili_api/bili_api.dart';
import 'package:bilisail/features/playback/data/play_info_merge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('App supplement adds high-tier video and every audio format', () {
    final primary = _info(
      videos: [_track(80, 'avc1.640028', bandwidth: 1000)],
      audios: [_track(30280, 'mp4a.40.2', bandwidth: 192000)],
      accepted: [80],
    );
    final supplement = _info(
      videos: [
        _track(120, 'avc1.640032', bandwidth: 8000),
        _track(126, 'dvh1.05.06', bandwidth: 10000),
        _track(80, 'avc1.640028', bandwidth: 2000),
      ],
      audios: [
        _track(30216, 'mp4a.40.5', bandwidth: 64000),
        _track(30232, 'mp4a.40.29', bandwidth: 132000),
        _track(30251, 'fLaC', bandwidth: 800000),
        _track(30250, 'ec-3', bandwidth: 640000),
      ],
      accepted: [126, 120, 80],
    );

    final merged = mergeApiPlayInfo(primary, supplement);
    expect(merged.dashVideo.map((track) => track.id), [80, 120, 126, 80]);
    expect(merged.dashVideo.last.bandwidth, 2000);
    expect(merged.dashAudio.map((track) => track.id), [
      30280,
      30216,
      30232,
      30251,
      30250,
    ]);
    expect(merged.acceptQuality, [126, 120, 80]);
    expect(merged.isPreview, isFalse);
    expect(merged.isIntentionallySilent, isFalse);
  });

  test('exact duplicate tracks do not grow the response', () {
    final track = _track(80, 'avc1.640028');
    final primary = _info(videos: [track], audios: const []);
    final supplement = _info(videos: [track], audios: const []);
    expect(mergeApiPlayInfo(primary, supplement), same(primary));
  });

  test('URL-only variants do not create a merged response', () {
    final primary = _info(
      videos: [_track(80, 'avc1.640028', bandwidth: 1000)],
      audios: [_track(30280, 'mp4a.40.2', bandwidth: 192000)],
    );
    final supplement = _info(
      videos: [
        _track(
          80,
          'avc1.640028',
          bandwidth: 1000,
          url: Uri.parse(
            'https://upos-sz-mirror.bilivideo.com/80-avc1.640028-1000.m4s?deadline=2',
          ),
        ),
      ],
      audios: [
        _track(
          30280,
          'mp4a.40.2',
          bandwidth: 192000,
          url: Uri.parse('https://app-cdn.example/refresh/audio.m4s'),
        ),
      ],
    );

    expect(mergeApiPlayInfo(primary, supplement), same(primary));
  });

  test('real additions still exclude URL-only variants', () {
    final primary = _info(
      videos: [_track(80, 'avc1.640028', bandwidth: 1000)],
      audios: [_track(30280, 'mp4a.40.2', bandwidth: 192000)],
    );
    final supplement = _info(
      videos: [
        _track(
          80,
          'avc1.640028',
          bandwidth: 1000,
          url: Uri.parse('https://app-cdn.example/refresh/video.m4s'),
        ),
        _track(120, 'avc1.640032', bandwidth: 8000),
      ],
      audios: [
        _track(
          30280,
          'mp4a.40.2',
          bandwidth: 192000,
          url: Uri.parse('https://app-cdn.example/refresh/audio.m4s'),
        ),
        _track(30232, 'mp4a.40.29', bandwidth: 132000),
      ],
      accepted: [120, 80],
    );

    final merged = mergeApiPlayInfo(primary, supplement);
    expect(merged.dashVideo.map((track) => track.id), [80, 120]);
    expect(merged.dashAudio.map((track) => track.id), [30280, 30232]);
  });

  for (final reason in ['preview', 'duration', 'voice']) {
    test('rejects an incompatible supplement: $reason', () {
      final primary = _info(
        videos: [_track(80, 'avc1')],
        audios: [_track(30280, 'mp4a.40.2')],
      );
      final supplement = _info(
        videos: [_track(120, 'avc1')],
        audios: [_track(30251, 'fLaC')],
        preview: reason == 'preview',
        duration: reason == 'duration'
            ? const Duration(seconds: 20)
            : const Duration(seconds: 60),
        language: reason == 'voice' ? 'en' : '',
        productionType: reason == 'voice' ? 1 : 0,
      );
      expect(mergeApiPlayInfo(primary, supplement), same(primary));
    });
  }
}

ApiPlayInfo _info({
  required List<ApiMediaTrack> videos,
  required List<ApiMediaTrack> audios,
  List<int> accepted = const [80],
  bool preview = false,
  Duration duration = const Duration(seconds: 60),
  String language = '',
  int productionType = 0,
}) => ApiPlayInfo(
  duration: duration,
  dashVideo: videos,
  dashAudio: audios,
  acceptQuality: accepted,
  isPreview: preview,
  isIntentionallySilent: audios.isEmpty,
  currentLanguage: language,
  productionType: productionType,
);

ApiMediaTrack _track(int id, String codec, {int bandwidth = 1000, Uri? url}) =>
    ApiMediaTrack(
      id: id,
      url:
          url ??
          Uri.parse(
            'https://upos-sz-mirror.bilivideo.com/$id-$codec-$bandwidth.m4s',
          ),
      backupUrls: const [],
      bandwidth: bandwidth,
      mimeType: id > 30000 ? 'audio/mp4' : 'video/mp4',
      codecs: codec,
    );
