import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../domain/pgc_resolver_health.dart';
import '../domain/pgc_resolver_preset.dart';

/// User-hosted PGC resolver endpoints. No account credential controls live here.
final class PgcResolverSettingsSection extends StatefulWidget {
  const PgcResolverSettingsSection({
    super.key,
    required this.enabled,
    required this.servers,
    required this.defaultRegion,
    required this.onEnabledChanged,
    required this.onServerChanged,
    required this.onApplyPreset,
    required this.onDefaultRegionChanged,
    this.healthChecker,
    this.presets = PgcResolverPresets.all,
  });

  final bool enabled;
  final Map<String, String> servers;
  final String defaultRegion;
  final Future<void> Function(bool enabled) onEnabledChanged;
  final Future<void> Function(String region, String value) onServerChanged;

  /// Writes every region a preset covers and enables the feature in one save.
  final Future<void> Function(Map<String, String> servers) onApplyPreset;

  final Future<void> Function(String region) onDefaultRegionChanged;

  /// Null hides the check actions instead of showing buttons that always fail.
  final PgcResolverHealthChecker? healthChecker;
  final List<PgcResolverPreset> presets;

  @override
  State<PgcResolverSettingsSection> createState() =>
      _PgcResolverSettingsSectionState();
}

/// Canonical order used for labels, checks and the default-region list.
const _regionOrder = ['hk', 'tw'];
const _labels = {'hk': '香港／澳门', 'tw': '台湾'};

final class _PgcResolverSettingsSectionState
    extends State<PgcResolverSettingsSection> {
  /// Region keys or preset ids with an in-flight check.
  final _checking = <String>{};

  PgcResolverPreset? get _matchedPreset {
    for (final preset in widget.presets) {
      for (final region in preset.regions) {
        final value = widget.servers[region] ?? '';
        if (value.isNotEmpty &&
            PgcResolverPresets.sameServer(preset.url, value)) {
          return preset;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final configured = widget.servers.values
        .where((url) => url.isNotEmpty)
        .length;
    final matched = _matchedPreset;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('番剧地区解锁'),
          subtitle: Text(
            widget.enabled
                ? '已配置 $configured 个地区；详情或播放被地区拒绝时回退到所选服务器'
                : '需要自行准备兼容 BBZQ 的解析服务器，或从推荐列表选择，默认不发送账号凭据',
          ),
          value: widget.enabled,
          onChanged: (value) => unawaited(widget.onEnabledChanged(value)),
        ),
        if (widget.enabled) ...[
          for (final region in _regionOrder)
            ListTile(
              key: ValueKey('pgc-resolver-$region'),
              contentPadding: EdgeInsets.zero,
              title: Text(_labels[region]!),
              subtitle: Text(
                _serverLabel(region),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.healthChecker != null &&
                      (widget.servers[region] ?? '').isNotEmpty)
                    _checkButton(
                      key: ValueKey('pgc-resolver-check-$region'),
                      label: '检测该地址',
                      busy: _checking.contains(region),
                      onPressed: () =>
                          _checkAddress(region, widget.servers[region]!),
                    ),
                  const Icon(Icons.edit_outlined),
                ],
              ),
              onTap: () => unawaited(_editServer(context, region)),
            ),
          ListTile(
            key: const ValueKey('pgc-resolver-presets'),
            contentPadding: EdgeInsets.zero,
            title: const Text('推荐解析服务器'),
            subtitle: Text(
              matched == null
                  ? '未使用推荐服务器；可从已实测的公共列表一键填入'
                  : '${matched.name} · ${_areasLabel(matched.regions)}'
                        '（${matched.verifiedOn} 实测）',
              maxLines: 2,
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.presets.isEmpty
                ? null
                : () => unawaited(_pickPreset(context)),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('默认解析地区'),
            subtitle: const Text('优先询问该地区；失败后按港澳、台湾顺序继续'),
            trailing: DropdownButton<String>(
              key: const ValueKey('pgc-resolver-default-region'),
              value: widget.defaultRegion,
              items: [
                const DropdownMenuItem(value: '', child: Text('自动')),
                for (final region in _regionOrder)
                  DropdownMenuItem(
                    value: region,
                    child: Text(_labels[region]!),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  unawaited(widget.onDefaultRegionChanged(value));
                }
              },
            ),
          ),
          const Text(
            '仅官方详情或取流被拒绝时尝试解析。账号 Cookie 与访问密钥默认不发送；'
            '检测使用同一匿名链路，不会登录或写入账号信息。'
            '搜索合并、字幕补源和番剧下载不在本次接入范围。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ],
    );
  }

  String _serverLabel(String region) {
    final value = widget.servers[region] ?? '';
    if (value.isEmpty) return '未配置';
    final preset = PgcResolverPresets.matching(value);
    return preset == null ? value : '$value（推荐：${preset.name}）';
  }

  static String _areasLabel(Set<String> regions) => _regionOrder
      .where(regions.contains)
      .map((region) => _labels[region]!)
      .join('／');

  String _primaryRegion(PgcResolverPreset preset) => _regionOrder.firstWhere(
    preset.regions.contains,
    orElse: () => preset.regions.first,
  );

  Widget _checkButton({
    required Key key,
    required String label,
    required bool busy,
    required VoidCallback onPressed,
  }) => IconButton(
    key: key,
    tooltip: label,
    icon: busy
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.network_check_outlined),
    onPressed: busy ? null : onPressed,
  );

  /// Uses the state's own context so the mounted guard matches the frame that
  /// is read after the await.
  Future<void> _checkAddress(
    String key,
    String baseUrl, {
    String? region,
  }) async {
    final checker = widget.healthChecker;
    if (checker == null) return;
    final area = region ?? key;
    setState(() => _checking.add(key));
    try {
      final health = await checker.check(baseUrl: baseUrl, region: area);
      if (mounted) {
        showAppNotice(context, '${_labels[area] ?? area}：${health.summary}');
      }
    } catch (_) {
      if (mounted) showAppNotice(context, '检测失败，请稍后重试');
    } finally {
      if (mounted) setState(() => _checking.remove(key));
    }
  }

  Future<void> _editServer(BuildContext context, String region) async {
    final form = GlobalKey<FormState>();
    var next = widget.servers[region] ?? '';
    var saving = false;
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('${_labels[region]}解析服务器'),
          content: Form(
            key: form,
            child: TextFormField(
              initialValue: next,
              enabled: !saving,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '服务器地址',
                hintText: 'https://resolver.example.com',
                helperText: '留空可停用该地区；支持 HTTP/HTTPS，不包含账号信息',
              ),
              onChanged: (value) => next = value,
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return null;
                return PgcResolverPresets.isValidUrl(text)
                    ? null
                    : '请输入有效的 HTTP/HTTPS 服务器地址';
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (form.currentState?.validate() != true) return;
                      setState(() => saving = true);
                      try {
                        await widget.onServerChanged(region, next.trim());
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (_) {
                        if (dialogContext.mounted) {
                          setState(() => saving = false);
                        }
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPreset(BuildContext context) async {
    final health = <String, PgcResolverHealth?>{};
    final checking = <String>{};
    var applying = '';
    await showAppDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('推荐解析服务器'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '以下地址已通过匿名详情与取流检测，可直接填入对应地区。'
                    '公共服务器由志愿者维护，失效后请重新检测或换用自建服务器。',
                    style: TextStyle(fontSize: 12),
                  ),
                  for (final preset in widget.presets) ...[
                    const SizedBox(height: 12),
                    _presetCard(
                      preset,
                      health: health[preset.id],
                      busy:
                          checking.contains(preset.id) || applying == preset.id,
                      canCheck: widget.healthChecker != null,
                      onCheck: () => unawaited(
                        _checkPreset(
                          dialogContext,
                          setDialogState,
                          preset,
                          health,
                          checking,
                        ),
                      ),
                      onApply: applying.isNotEmpty
                          ? null
                          : () async {
                              setDialogState(() => applying = preset.id);
                              try {
                                await widget.onApplyPreset({
                                  for (final region in preset.regions)
                                    region: preset.url,
                                });
                                if (dialogContext.mounted) {
                                  Navigator.pop(dialogContext);
                                }
                                if (context.mounted) {
                                  showAppNotice(context, '已应用 ${preset.name}');
                                }
                              } catch (_) {
                                if (dialogContext.mounted) {
                                  setDialogState(() => applying = '');
                                  showAppNotice(context, '设置保存失败，请重试');
                                }
                              }
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: widget.healthChecker == null
                  ? null
                  : () => unawaited(
                      _checkAllPresets(
                        dialogContext,
                        setDialogState,
                        health,
                        checking,
                      ),
                    ),
              child: const Text('全部检测'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _presetCard(
    PgcResolverPreset preset, {
    required PgcResolverHealth? health,
    required bool busy,
    required bool canCheck,
    required VoidCallback onCheck,
    required VoidCallback? onApply,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    preset.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  health == null ? '未检测' : (busy ? '检测中…' : health.summary),
                  style: TextStyle(
                    fontSize: 12,
                    color: health?.usable == true
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              preset.url,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 4),
            Text(
              '适用地区：${_areasLabel(preset.regions)} · '
              '${preset.verifiedOn} 实测',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(preset.note, style: const TextStyle(fontSize: 12)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (canCheck)
                  TextButton(
                    key: ValueKey('pgc-resolver-preset-check-${preset.id}'),
                    onPressed: busy ? null : onCheck,
                    child: const Text('检测'),
                  ),
                TextButton(
                  key: ValueKey('pgc-resolver-preset-apply-${preset.id}'),
                  onPressed: onApply,
                  child: const Text('填入'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Runs one check for [preset]; [dialogContext] keeps a closed dialog from
  /// being updated after its state is disposed.
  Future<void> _checkPreset(
    BuildContext dialogContext,
    StateSetter setDialogState,
    PgcResolverPreset preset,
    Map<String, PgcResolverHealth?> health,
    Set<String> checking,
  ) async {
    final checker = widget.healthChecker;
    if (checker == null || checking.contains(preset.id)) return;
    setDialogState(() => checking.add(preset.id));
    PgcResolverHealth result;
    try {
      result = await checker.check(
        baseUrl: preset.url,
        region: _primaryRegion(preset),
      );
    } catch (_) {
      result = const PgcResolverHealth.failed(failure: '检测失败');
    }
    if (!dialogContext.mounted) return;
    health[preset.id] = result;
    checking.remove(preset.id);
    setDialogState(() {});
  }

  Future<void> _checkAllPresets(
    BuildContext dialogContext,
    StateSetter setDialogState,
    Map<String, PgcResolverHealth?> health,
    Set<String> checking,
  ) async {
    for (final preset in widget.presets) {
      if (!dialogContext.mounted) return;
      await _checkPreset(
        dialogContext,
        setDialogState,
        preset,
        health,
        checking,
      );
    }
  }
}
