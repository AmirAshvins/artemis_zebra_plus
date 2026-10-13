import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';

/// Global diagnostic logging switches for the artemis_zebra_plus plugin.
class ArtemisZebraPlusLogging {
  ArtemisZebraPlusLogging._();

  static const MethodChannel _channel = MethodChannel('artemis_zebra_plus');

  /// When true, suppresses package diagnostics, including native iOS traces.
  static bool silentLogs = true;

  /// Updates package logging behavior.
  ///
  /// Host apps typically call this once at bootstrap, e.g. from a feature flag.
  /// Native iOS starts silent, then follows this value. A missing plugin (unit
  /// tests) is ignored.
  static void configure({bool? silentLogs}) {
    if (silentLogs == null) {
      return;
    }
    ArtemisZebraPlusLogging.silentLogs = silentLogs;
    unawaited(_pushSilentLogs(silentLogs));
  }

  static Future<void> _pushSilentLogs(bool silent) async {
    try {
      await _channel.invokeMethod<void>('setSilentLogs', silent);
    } catch (_) {
      // Tests and desktop hosts have no iOS plugin.
    }
  }
}

/// Logs a diagnostic message when [ArtemisZebraPlusLogging.silentLogs] is false.
void zebraPackageLog(String message) {
  if (ArtemisZebraPlusLogging.silentLogs) {
    return;
  }
  dev.log(message, name: 'ArtemisZebra');
}

/// Connect, print, and link-loss traces. Hidden while
/// [ArtemisZebraPlusLogging.silentLogs] is true.
void zebraTrace(String message) {
  if (ArtemisZebraPlusLogging.silentLogs) {
    return;
  }
  // ignore: avoid_print
  print('[Zebra] $message');
}

/// Prints a diagnostic message when [ArtemisZebraPlusLogging.silentLogs] is false.
void zebraPackagePrint(String message) {
  if (ArtemisZebraPlusLogging.silentLogs) {
    return;
  }
  // ignore: avoid_print
  print(message);
}
