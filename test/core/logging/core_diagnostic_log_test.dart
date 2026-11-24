import 'dart:convert';
import 'dart:io';

import 'package:bilisail/core/logging/core_diagnostic_log.dart';
import 'package:bilisail/core/logging/diagnostic_log_writer.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bili_api/bili_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('core_logs_');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  Future<File> singleLogFile() {
    return directory
        .list()
        .where((entity) => entity is File)
        .cast<File>()
        .single;
  }

  Future<List<Map<String, Object?>>> readEvents() async {
    final lines = await (await singleLogFile()).readAsLines();
    return lines
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList(growable: false);
  }

  test(
    'core errors retain categories and safe locations, never raw secrets',
    () async {
      final log = CoreDiagnosticLog(directory);
      log.record(
        CoreDiagnosticEvent.frameworkError,
        error: const AppFailure(
          AppFailureKind.network,
          'Cookie: SESSDATA=SECRET https://cdn.test/a?token=SECRET',
        ),
        stack: StackTrace.fromString(
          '#0 request (package:bilisail/core/network/api_requests.dart:14:2)\n'
          '#1 secret (C:/Users/PrivatePerson/token=SECRET.dart:2:4)\n'
          '#2 other (https://example.test/SECRET:1:1)\n',
        ),
      );
      await log.close();
      final file = await directory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .single;
      final text = await file.readAsString();
      final json = jsonDecode(text) as Map<String, Object?>;
      expect(json['failure'], 'network');
      expect(json['stack'], [
        'package:bilisail/core/network/api_requests.dart:14:2',
      ]);
      expect(text, isNot(contains('SECRET')));
      expect(text, isNot(contains('PrivatePerson')));
      expect(text, isNot(contains('Cookie')));
    },
  );

  test('API successes, errors and session transitions are included', () async {
    final log = CoreDiagnosticLog(directory);
    final requests = ApiRequests(diagnostics: log);
    expect(await requests.run((_) async => 42), 42);
    await expectLater(
      requests.run<void>((_) async {
        throw const ApiFailure(ApiFailureCategory.timeout, 'SECRET');
      }),
      throwsA(isA<AppFailure>()),
    );
    requests.advanceSession();
    await log.close();
    final file = await directory
        .list()
        .where((e) => e is File)
        .cast<File>()
        .single;
    final lines = await file.readAsLines();
    expect(lines, hasLength(3));
    expect(lines[0], contains('"outcome":"success"'));
    expect(lines[1], contains('"failure":"timeout"'));
    expect(lines[2], contains('sessionChanged'));
    expect(lines.join(), isNot(contains('SECRET')));
  });

  test(
    'play info resolution records safe fields and allowed sources',
    () async {
      final log = CoreDiagnosticLog(directory);
      log.record(
        CoreDiagnosticEvent.playInfoResolved,
        requestedQuality: 127,
        selectedQuality: 116,
        videoQualities: <Object?>[127, '120', 0, -1, 116.0, 116],
        audioQualities: <Object?>[30280, 30232],
        playSource: 'web',
      );
      log.record(CoreDiagnosticEvent.playInfoResolved, playSource: 'app');
      log.record(CoreDiagnosticEvent.playInfoResolved, playSource: 'merged');
      await log.close();

      final events = await readEvents();
      expect(events, hasLength(3));
      expect(events[0]['event'], 'playInfoResolved');
      expect(events[0]['requestedQuality'], 127);
      expect(events[0]['selectedQuality'], 116);
      expect(events[0]['videoQualities'], [127, 116]);
      expect(events[0]['audioQualities'], [30280, 30232]);
      expect(events.map((event) => event['playSource']), [
        'web',
        'app',
        'merged',
      ]);
    },
  );

  test(
    'play info resolution filters invalid values and bounds lists',
    () async {
      final log = CoreDiagnosticLog(directory);
      const unsafeSource =
          'https://cdn.test/BV1SECRET?account=SECRET&token=SECRET';
      log.record(
        CoreDiagnosticEvent.playInfoResolved,
        requestedQuality: 0,
        selectedQuality: -116,
        videoQualities: <Object?>[
          0,
          -1,
          '127',
          127.0,
          false,
          null,
          for (var quality = 1; quality <= 40; quality++) quality,
        ],
        audioQualities: <Object?>[
          for (var quality = 1; quality <= 40; quality++) 30000 + quality,
        ],
        playSource: unsafeSource,
      );
      log.record(
        CoreDiagnosticEvent.playInfoResolved,
        videoQualities: <Object?>[0, -1, '116'],
        audioQualities: <Object?>[],
        playSource: 'WEB',
      );
      await log.close();

      final text = await (await singleLogFile()).readAsString();
      final events = await readEvents();
      expect(events, hasLength(2));
      expect(events[0].containsKey('requestedQuality'), isFalse);
      expect(events[0].containsKey('selectedQuality'), isFalse);
      expect(events[0].containsKey('playSource'), isFalse);
      expect(
        events[0]['videoQualities'],
        List.generate(32, (index) => index + 1),
      );
      expect(
        events[0]['audioQualities'],
        List.generate(32, (index) => 30001 + index),
      );
      expect(events[1]['videoQualities'], isEmpty);
      expect(events[1]['audioQualities'], isEmpty);
      expect(events[1].containsKey('playSource'), isFalse);
      expect(text, isNot(contains('BV1SECRET')));
      expect(text, isNot(contains('SECRET')));
    },
  );

  test('App protocol diagnostics use a fixed protocol allowlist', () async {
    final log = CoreDiagnosticLog(directory);
    log.record(
      CoreDiagnosticEvent.appPlayInfoResolved,
      appProtocol: 'playview',
      requestedQuality: 127,
      trialRequested: true,
      videoQualities: const [126, 120],
    );
    log.record(
      CoreDiagnosticEvent.appPlayInfoResolved,
      appProtocol: 'https://SECRET.invalid/?token=SECRET',
    );
    await log.close();

    final events = await readEvents();
    expect(events[0]['appProtocol'], 'playview');
    expect(events[0]['trialRequested'], isTrue);
    expect(events[1].containsKey('appProtocol'), isFalse);
    expect(events[1].containsKey('trialRequested'), isFalse);
    expect(
      (await (await singleLogFile()).readAsString()),
      isNot(contains('SECRET')),
    );
  });

  test('omitted play info fields preserve the existing event shape', () async {
    final log = CoreDiagnosticLog(directory);
    log.record(CoreDiagnosticEvent.ready);
    log.record(CoreDiagnosticEvent.playInfoResolved);
    await log.close();

    final events = await readEvents();
    expect(events.map((event) => event['event']), [
      'ready',
      'playInfoResolved',
    ]);
    for (final event in events) {
      expect(event.keys, ['time', 'event']);
    }
  });

  test(
    'rotation keeps both channels and bounds files across restarts',
    () async {
      for (var i = 0; i < 10; i++) {
        for (final channel in DiagnosticLogChannel.values) {
          final writer = DiagnosticLogWriter(directory, channel, maxBytes: 128);
          await writer.initialize();
          for (var j = 0; j < 10; j++) {
            writer.record({'event': 'bounded', 'value': j});
            await writer.flush();
          }
          await writer.close();
        }
      }
      final files = await directory
          .list()
          .where((e) => e is File)
          .cast<File>()
          .toList();
      for (final channel in DiagnosticLogChannel.values) {
        final own = files.where(
          (f) => p.basename(f.path).startsWith('${channel.name}-'),
        );
        expect(own.length, lessThanOrEqualTo(6));
        expect(own, isNotEmpty);
      }
      for (final file in files) {
        expect(await file.length(), lessThanOrEqualTo(128));
      }
    },
  );
}
