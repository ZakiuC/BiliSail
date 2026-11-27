import 'dart:io';

import 'package:bilisail/features/settings/data/bili_api_pgc_resolver_health.dart';
import 'package:bilisail/features/settings/domain/pgc_resolver_preset.dart';
import 'package:flutter_test/flutter_test.dart';

/// Opt-in live check: the default test run stays offline, so a shipped preset
/// is never re-verified silently. Run with:
///
/// ```
/// PGC_RESOLVER_LIVE=1 flutter test --no-pub \
///   test/features/settings/pgc_resolver_live_check_test.dart
/// ```
void main() {
  final live = Platform.environment['PGC_RESOLVER_LIVE'] == '1';

  test(
    'every shipped preset answers the anonymous season and playurl check',
    () async {
      final checker = BiliApiPgcResolverHealth();
      for (final preset in PgcResolverPresets.all) {
        for (final region in preset.regions) {
          final health = await checker.check(
            baseUrl: preset.url,
            region: region,
          );
          expect(
            health.usable,
            isTrue,
            reason: '${preset.id} ($region): ${health.summary}',
          );
        }
      }
    },
    skip: live
        ? false
        : 'Set PGC_RESOLVER_LIVE=1 to contact the public resolver servers.',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
