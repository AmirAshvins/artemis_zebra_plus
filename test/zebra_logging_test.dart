import 'package:artemis_zebra_plus/zebra_logging.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    ArtemisZebraPlusLogging.configure(silentLogs: true);
  });

  test('zebraPackageLog is silent by default', () {
    ArtemisZebraPlusLogging.configure(silentLogs: true);
    expect(ArtemisZebraPlusLogging.silentLogs, isTrue);
    // Should not throw when silent.
    zebraPackageLog('test message');
    zebraPackagePrint('test print');
  });

  test('configure can enable diagnostics', () {
    ArtemisZebraPlusLogging.configure(silentLogs: false);
    expect(ArtemisZebraPlusLogging.silentLogs, isFalse);
    zebraPackageLog('enabled');
  });
}
