import 'package:bilisail/features/settings/domain/pgc_resolver_preset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shipped presets are valid anonymous resolver addresses', () {
    expect(PgcResolverPresets.all, isNotEmpty);
    final ids = <String>{};
    for (final preset in PgcResolverPresets.all) {
      expect(ids.add(preset.id), isTrue, reason: 'duplicate ${preset.id}');
      expect(PgcResolverPresets.isValidPreset(preset), isTrue);
      expect(preset.name, isNotEmpty);
      expect(preset.note, isNotEmpty);
      expect(preset.url, startsWith('https://'));
      expect(preset.verifiedOn, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    }
  });

  test('address validation rejects credentials, query and fragment', () {
    expect(PgcResolverPresets.isValidUrl('https://bili.example.com'), isTrue);
    expect(PgcResolverPresets.isValidUrl('http://127.0.0.1:8080/'), isTrue);
    expect(PgcResolverPresets.isValidUrl(''), isFalse);
    expect(PgcResolverPresets.isValidUrl('bili.example.com'), isFalse);
    expect(PgcResolverPresets.isValidUrl('ftp://bili.example.com'), isFalse);
    expect(
      PgcResolverPresets.isValidUrl('https://user:pass@bili.example.com'),
      isFalse,
    );
    expect(
      PgcResolverPresets.isValidUrl('https://bili.example.com?a=1'),
      isFalse,
    );
    expect(
      PgcResolverPresets.isValidUrl('https://bili.example.com#x'),
      isFalse,
    );
  });

  test('matching ignores case and a trailing slash', () {
    const preset = PgcResolverPreset(
      id: 'example',
      name: 'Example',
      url: 'https://bili.example.com',
      regions: {'hk'},
      note: 'note',
      verifiedOn: '2026-11-27',
    );
    expect(PgcResolverPresets.sameServer(preset.url, preset.url), isTrue);
    expect(
      PgcResolverPresets.sameServer(preset.url, 'https://BILI.example.com/'),
      isTrue,
    );
    expect(
      PgcResolverPresets.sameServer(preset.url, 'https://bili.example.com/'),
      isTrue,
    );
    expect(
      PgcResolverPresets.sameServer(preset.url, 'https://other.example.com'),
      isFalse,
    );
    expect(PgcResolverPresets.sameServer(preset.url, ''), isFalse);
  });

  test('matching returns the shipped preset for its own address', () {
    for (final preset in PgcResolverPresets.all) {
      expect(PgcResolverPresets.matching(preset.url)?.id, preset.id);
      expect(PgcResolverPresets.matching('${preset.url}/')?.id, preset.id);
    }
    expect(PgcResolverPresets.matching('https://unknown.example.com'), isNull);
  });
}
