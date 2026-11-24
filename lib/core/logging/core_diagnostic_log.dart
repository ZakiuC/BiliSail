import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/app_failure.dart';
import 'diagnostic_log_writer.dart';

enum CoreDiagnosticEvent {
  startup,
  ready,
  shutdown,
  bootstrapFailure,
  frameworkError,
  unhandledError,
  requestFinished,
  playInfoResolved,
  appPlayInfoResolved,
  sessionChanged,
  downloadState,
  downloadMediaScan,
  downloadPhotosExport,
  logExported,
  logExportFailed,
}

enum CoreDiagnosticOutcome { success, cancelled, failed }

/// No exception messages, URLs, headers, user content or account identifiers.
final class CoreDiagnosticLog {
  CoreDiagnosticLog(Directory directory, {int maxBytes = 256 * 1024})
    : _writer = DiagnosticLogWriter(
        directory,
        DiagnosticLogChannel.core,
        maxBytes: maxBytes,
      );

  final DiagnosticLogWriter _writer;
  Directory get directory => _writer.directory;

  static Future<CoreDiagnosticLog?> create() async {
    try {
      final root = await getApplicationSupportDirectory();
      final log = CoreDiagnosticLog(Directory(p.join(root.path, 'logs')));
      await log._writer.initialize();
      return log;
    } on FileSystemException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  void record(
    CoreDiagnosticEvent event, {
    Object? error,
    StackTrace? stack,
    Duration? elapsed,
    CoreDiagnosticOutcome? outcome,
    int? active,
    int? queued,
    int? failed,
    String? mediaFormat,
    String? mediaScanResult,
    int? requestedQuality,
    int? selectedQuality,
    List<Object?>? videoQualities,
    List<Object?>? audioQualities,
    String? playSource,
    String? appProtocol,
    bool? trialRequested,
  }) {
    _writer.record({
      'time': DateTime.now().toUtc().toIso8601String(),
      'event': event.name,
      'outcome': ?outcome?.name,
      'elapsedMs': ?elapsed?.inMilliseconds,
      'active': ?active,
      'queued': ?queued,
      'failed': ?failed,
      'mediaFormat': ?mediaFormat,
      'mediaScanResult': ?mediaScanResult,
      'requestedQuality': ?_positiveQuality(requestedQuality),
      'selectedQuality': ?_positiveQuality(selectedQuality),
      'videoQualities': ?_qualityList(videoQualities),
      'audioQualities': ?_qualityList(audioQualities),
      'playSource': ?_safePlaySource(playSource),
      'appProtocol': ?_safeAppProtocol(appProtocol),
      'trialRequested': ?trialRequested,
      if (error != null) 'errorType': _safeType(error),
      if (error is AppFailure) 'failure': error.kind.name,
      if (stack != null) 'stack': _safeStack(stack),
    });
  }

  static int? _positiveQuality(int? quality) =>
      quality != null && quality > 0 ? quality : null;

  static List<int>? _qualityList(List<Object?>? qualities) {
    if (qualities == null) return null;
    return qualities
        .whereType<int>()
        .where((quality) => quality > 0)
        .take(32)
        .toList(growable: false);
  }

  static String? _safePlaySource(String? playSource) =>
      const {'web', 'app', 'merged'}.contains(playSource) ? playSource : null;

  static String? _safeAppProtocol(String? protocol) =>
      const {'playview', 'playview_phone', 'json'}.contains(protocol)
      ? protocol
      : null;

  static String _safeType(Object error) {
    final type = error.runtimeType.toString();
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_<>?, ]{0,95}$').hasMatch(type)
        ? type
        : 'Error';
  }

  static List<String> _safeStack(StackTrace stack) {
    // Retain package/Dart locations only, never local paths or raw frame text.
    final pattern = RegExp(
      r'\((package:[a-zA-Z0-9_]+/[a-zA-Z0-9_./-]+\.dart|dart:[a-zA-Z0-9_./-]+):(\d+)(?::(\d+))?\)$',
    );
    return [
      for (final line in stack.toString().split('\n').take(64))
        if (pattern.firstMatch(line.trim()) case final match?)
          '${match.group(1)}:${match.group(2)}:${match.group(3) ?? '0'}',
    ].take(16).toList();
  }

  Future<void> flush() => _writer.flush();
  Future<void> close() => _writer.close();
}
