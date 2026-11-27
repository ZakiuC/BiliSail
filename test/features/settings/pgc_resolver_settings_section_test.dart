import 'package:bilisail/features/settings/domain/pgc_resolver_health.dart';
import 'package:bilisail/features/settings/domain/pgc_resolver_preset.dart';
import 'package:bilisail/features/settings/presentation/pgc_resolver_settings_section.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeHealth implements PgcResolverHealthChecker {
  _FakeHealth([this.result]);

  final PgcResolverHealth? result;
  final calls = <(String, String)>[];

  @override
  Future<PgcResolverHealth> check({
    required String baseUrl,
    required String region,
  }) async {
    calls.add((baseUrl, region));
    return result ??
        const PgcResolverHealth(
          seasonReady: true,
          playbackReady: true,
          latency: Duration(milliseconds: 1200),
        );
  }
}

Widget _host({
  required bool enabled,
  required Map<String, String> servers,
  String defaultRegion = '',
  Future<void> Function(bool)? onEnabledChanged,
  Future<void> Function(String, String)? onServerChanged,
  Future<void> Function(Map<String, String>)? onApplyPreset,
  Future<void> Function(String)? onDefaultRegionChanged,
  PgcResolverHealthChecker? health,
}) => MaterialApp(
  builder: AppNoticeHost.builder,
  home: Scaffold(
    body: StatefulBuilder(
      builder: (context, setState) => SingleChildScrollView(
        child: PgcResolverSettingsSection(
          enabled: enabled,
          servers: servers,
          defaultRegion: defaultRegion,
          onEnabledChanged: (value) async {
            await onEnabledChanged?.call(value);
            setState(() => enabled = value);
          },
          onServerChanged: (region, value) async {
            await onServerChanged?.call(region, value);
            setState(() => servers[region] = value);
          },
          onApplyPreset: (values) async {
            await onApplyPreset?.call(values);
            setState(() => servers.addAll(values));
          },
          onDefaultRegionChanged: (value) async {
            await onDefaultRegionChanged?.call(value);
            setState(() => defaultRegion = value);
          },
          healthChecker: health,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('resolver settings validate, save and choose a region', (
    tester,
  ) async {
    var enabled = false;
    var defaultRegion = '';
    final servers = <String, String>{'hk': '', 'tw': ''};
    await tester.pumpWidget(
      _host(
        enabled: enabled,
        servers: servers,
        defaultRegion: defaultRegion,
        onEnabledChanged: (value) async => enabled = value,
        onServerChanged: (region, value) async => servers[region] = value,
        onDefaultRegionChanged: (value) async => defaultRegion = value,
      ),
    );
    expect(find.byKey(const ValueKey('pgc-resolver-hk')), findsNothing);
    await tester.tap(find.text('番剧地区解锁'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pgc-resolver-hk')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pgc-resolver-hk')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'not a url');
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(find.text('请输入有效的 HTTP/HTTPS 服务器地址'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField),
      'https://hk.example.com/',
    );
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(servers['hk'], 'https://hk.example.com/');

    await tester.tap(find.byKey(const ValueKey('pgc-resolver-default-region')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('台湾').last);
    await tester.pumpAndSettle();
    expect(defaultRegion, 'tw');
  });

  testWidgets('recommended servers can be checked and filled in', (
    tester,
  ) async {
    final health = _FakeHealth();
    Map<String, String>? applied;
    final servers = <String, String>{'hk': '', 'tw': ''};
    await tester.pumpWidget(
      _host(
        enabled: true,
        servers: servers,
        onApplyPreset: (values) async => applied = values,
        health: health,
      ),
    );
    expect(find.text('未使用推荐服务器；可从已实测的公共列表一键填入'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pgc-resolver-presets')));
    await tester.pumpAndSettle();
    final preset = PgcResolverPresets.all.first;
    expect(find.text(preset.name), findsOneWidget);
    expect(find.textContaining('适用地区'), findsWidgets);

    await tester.tap(
      find.byKey(ValueKey('pgc-resolver-preset-check-${preset.id}')),
    );
    await tester.pumpAndSettle();
    expect(find.text('可用（1.2 秒）'), findsOneWidget);
    expect(health.calls.single.$1, preset.url);
    expect(preset.regions.contains(health.calls.single.$2), isTrue);

    await tester.tap(
      find.byKey(ValueKey('pgc-resolver-preset-apply-${preset.id}')),
    );
    await tester.pumpAndSettle();
    expect(applied, isNotNull);
    expect(applied!.values.toSet(), {preset.url});
    expect(applied!.keys.toSet(), preset.regions);
    // The notice confirms the applied preset and the tile now shows it.
    expect(find.text('已应用 ${preset.name}'), findsOneWidget);
  });

  testWidgets('configured addresses can be checked individually', (
    tester,
  ) async {
    final health = _FakeHealth(
      const PgcResolverHealth(
        seasonReady: true,
        playbackReady: false,
        latency: Duration(milliseconds: 800),
        failure: '服务器要求账号凭据',
      ),
    );
    await tester.pumpWidget(
      _host(
        enabled: true,
        servers: {'hk': 'https://hk.example.com', 'tw': ''},
        health: health,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pgc-resolver-check-hk')));
    await tester.pumpAndSettle();
    expect(health.calls.single.$1, 'https://hk.example.com');
    expect(find.text('香港／澳门：仅详情可用：服务器要求账号凭据'), findsOneWidget);
    // An empty region offers no check action.
    expect(find.byKey(const ValueKey('pgc-resolver-check-tw')), findsNothing);
  });

  testWidgets('without a checker the check actions stay hidden', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(enabled: true, servers: {'hk': 'https://hk.example.com', 'tw': ''}),
    );
    expect(find.byKey(const ValueKey('pgc-resolver-check-hk')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('pgc-resolver-presets')));
    await tester.pumpAndSettle();
    expect(find.text('检测'), findsNothing);
    expect(find.text('全部检测'), findsOneWidget);
  });
}
