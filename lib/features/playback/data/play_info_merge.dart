import 'package:bili_api/bili_api.dart';

/// Adds server-returned tracks from a second read of the same video.
///
/// Preview clips, mismatched durations and alternate voices must never leak
/// into the primary source. Exact duplicate tracks are ignored, while a real
/// higher-bitrate representation with the same quality/codec remains eligible.
ApiPlayInfo mergeApiPlayInfo(ApiPlayInfo primary, ApiPlayInfo supplement) {
  if (primary.isPreview || supplement.isPreview) return primary;
  if (primary.currentLanguage != supplement.currentLanguage ||
      primary.productionType != supplement.productionType) {
    return primary;
  }
  if (primary.duration > Duration.zero && supplement.duration > Duration.zero) {
    final difference = primary.duration > supplement.duration
        ? primary.duration - supplement.duration
        : supplement.duration - primary.duration;
    if (difference > const Duration(seconds: 2)) return primary;
  }

  final tracks = <ApiMediaTrack>[...primary.dashVideo, ...primary.dashAudio];
  final identities = tracks.map(_identity).toSet();
  var added = false;
  for (final track in [...supplement.dashVideo, ...supplement.dashAudio]) {
    if (identities.add(_identity(track))) added = true;
  }
  if (!added) return primary;

  final videoIdentities = primary.dashVideo.map(_identity).toSet();
  final audioIdentities = primary.dashAudio.map(_identity).toSet();
  return ApiPlayInfo(
    duration: primary.duration,
    dashVideo: List.unmodifiable([
      ...primary.dashVideo,
      for (final track in supplement.dashVideo)
        if (videoIdentities.add(_identity(track))) track,
    ]),
    dashAudio: List.unmodifiable([
      ...primary.dashAudio,
      for (final track in supplement.dashAudio)
        if (audioIdentities.add(_identity(track))) track,
    ]),
    isIntentionallySilent: primary.isIntentionallySilent,
    acceptQuality: List.unmodifiable(
      {...primary.acceptQuality, ...supplement.acceptQuality}.toList()
        ..sort((a, b) => b.compareTo(a)),
    ),
    loudness: primary.loudness ?? supplement.loudness,
    voices: primary.voices.isEmpty ? supplement.voices : primary.voices,
    currentLanguage: primary.currentLanguage,
    productionType: primary.productionType,
    pgcSkipSegments: primary.pgcSkipSegments,
  );
}

(String, int, String, int, String, Uri) _identity(ApiMediaTrack track) => (
  track.mimeType,
  track.id,
  track.codecs,
  track.bandwidth,
  track.url.path,
  track.url,
);
