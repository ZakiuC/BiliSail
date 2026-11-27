/// A public BBZQ-compatible resolver entry bundled with the app.
///
/// A preset only pre-fills the per-region addresses. Requests stay anonymous and
/// the user can replace the address at any time, so the app never treats a
/// preset as a trusted endpoint. Public servers are run by volunteers and stop
/// working without notice; [verifiedOn] records when the entry last passed the
/// in-app health check instead of promising future availability.
final class PgcResolverPreset {
  const PgcResolverPreset({
    required this.id,
    required this.name,
    required this.url,
    required this.regions,
    required this.note,
    required this.verifiedOn,
  });

  /// Stable identifier used by keys and tests, not shown to users.
  final String id;

  /// Operator-facing label shown in the picker.
  final String name;

  /// Base HTTP(S) address without credentials, query or fragment.
  final String url;

  /// Region keys shared with the persisted settings (`hk`, `tw`, `sea`, `cn`)
  /// that this address was verified for. Unlisted regions stay untouched.
  final Set<String> regions;

  final String note;

  /// ISO-8601 calendar date of the last successful in-app health check.
  final String verifiedOn;
}

/// Curated public resolver addresses.
///
/// Only addresses that passed an anonymous season and playurl check are added;
/// a community list entry alone is not enough. Re-verify with the in-app check
/// before releasing a new entry or changing [verifiedOn].
abstract final class PgcResolverPresets {
  static const all = <PgcResolverPreset>[
    PgcResolverPreset(
      id: 'lli',
      name: 'Lli 公共解析服务器',
      url: 'https://bili.lli.cx',
      regions: {'hk', 'tw'},
      note:
          '匿名反代，实测可解港澳台限定番剧的详情与取流；只代理 /pgc 路径，'
          '东南亚与大陆未验证。HTTPS 不可用时可改填 http://bili.lli.cx',
      verifiedOn: '2026-11-27',
    ),
    PgcResolverPreset(
      id: 'vercel-hk',
      name: 'Vercel HK 自建节点',
      url: 'https://resolver-vercel-beta.vercel.app',
      regions: {'hk', 'tw'},
      note:
          'Vercel hkg1 节点，biliroaming-ts-server 匿名配置；'
          'Web 取流可用，App 路径回退 Web；免费额度 100 GB-Hrs/月',
      verifiedOn: '2026-11-27',
    ),
  ];

  static const _regionKeys = {'hk', 'tw'};

  /// Whether [value] is a usable resolver address for a preset.
  static bool isValidUrl(String value) {
    final text = value.trim();
    if (text.isEmpty || text.length > 2048) return false;
    final uri = Uri.tryParse(text);
    return uri != null &&
        const {'http', 'https'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  /// Whether every region of [preset] is a known key and the address parses.
  static bool isValidPreset(PgcResolverPreset preset) =>
      preset.id.isNotEmpty &&
      preset.regions.isNotEmpty &&
      preset.regions.every(_regionKeys.contains) &&
      isValidUrl(preset.url);

  /// The preset whose address equals [url], ignoring scheme/host case and a
  /// trailing slash. Empty or unparsable addresses match nothing.
  static PgcResolverPreset? matching(String url) {
    for (final preset in all) {
      if (sameServer(preset.url, url)) return preset;
    }
    return null;
  }

  /// Compares two resolver addresses without treating cosmetic differences as a
  /// different server.
  static bool sameServer(String a, String b) {
    final left = _normalize(a);
    final right = _normalize(b);
    return left != null && left == right;
  }

  static String? _normalize(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final uri = Uri.tryParse(text);
    if (uri == null || uri.host.isEmpty) return null;
    final path = uri.path.endsWith('/')
        ? uri.path.substring(0, uri.path.length - 1)
        : uri.path;
    return '${uri.scheme.toLowerCase()}://'
        '${uri.host.toLowerCase()}${uri.hasPort ? ':${uri.port}' : ''}$path';
  }
}
