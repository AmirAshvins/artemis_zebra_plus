import 'dart:developer' as dev;

/// Global diagnostic logging switches for the artemis_zebra_plus plugin.
class ArtemisZebraPlusLogging {
  ArtemisZebraPlusLogging._();

  /// When true, suppresses all diagnostic [zebraPackageLog] / [zebraPackagePrint]
  /// output from the package.
  static bool silentLogs = true;

  /// Updates package logging behavior.
  ///
  /// Host apps typically call this once at bootstrap, e.g. from a feature flag.
  static void configure({bool? silentLogs}) {
    if (silentLogs != null) {
      ArtemisZebraPlusLogging.silentLogs = silentLogs;
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

/// Prints a diagnostic message when [ArtemisZebraPlusLogging.silentLogs] is false.
void zebraPackagePrint(String message) {
  if (ArtemisZebraPlusLogging.silentLogs) {
    return;
  }
  // ignore: avoid_print
  print(message);
}
