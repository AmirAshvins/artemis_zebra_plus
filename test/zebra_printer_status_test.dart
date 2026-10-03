import 'package:artemis_zebra_plus/artemis_zebra.dart';
import 'package:artemis_zebra_plus/zebra_link_status.dart';
import 'package:flutter_test/flutter_test.dart';

const Object _omitBattery = Object();

void main() {
  Map<String, dynamic> baseJson({Object? batteryPercent = _omitBattery}) {
    final json = <String, dynamic>{
      'isPaused': false,
      'numberOfFormatsInReceiveBuffer': 0,
      'isReadyToPrint': true,
      'isPaperOut': false,
      'isPartialFormatInProgress': false,
      'isReceiveBufferFull': false,
      'labelLengthInDots': 0,
      'isRibbonOut': false,
      'isHeadTooHot': false,
      'labelsRemainingInBatch': 0,
      'isHeadOpen': false,
      'isHeadCold': false,
      'printMode': 0,
    };
    if (!identical(batteryPercent, _omitBattery)) {
      json['batteryPercent'] = batteryPercent;
    }
    return json;
  }

  test('fromJson reads batteryPercent', () {
    final status = ZebraPrinterStatus.fromJson(baseJson(batteryPercent: 72));
    expect(status.batteryPercent, 72);
  });

  test('fromJson missing batteryPercent is null', () {
    final status = ZebraPrinterStatus.fromJson(baseJson());
    expect(status.batteryPercent, isNull);
  });

  test('fromJson null batteryPercent is null', () {
    final status = ZebraPrinterStatus.fromJson(baseJson(batteryPercent: null));
    expect(status.batteryPercent, isNull);
  });

  test('fromJson unparseable batteryPercent is null', () {
    final status = ZebraPrinterStatus.fromJson(baseJson(batteryPercent: 'na'));
    expect(status.batteryPercent, isNull);
  });

  test('parseBatteryPercent accepts percent suffix and bounds', () {
    expect(ZebraPrinterStatus.parseBatteryPercent('15%'), 15);
    expect(ZebraPrinterStatus.parseBatteryPercent(0), 0);
    expect(ZebraPrinterStatus.parseBatteryPercent(100), 100);
    expect(ZebraPrinterStatus.parseBatteryPercent(101), isNull);
    expect(ZebraPrinterStatus.parseBatteryPercent(''), isNull);
  });

  test('disconnected has null batteryPercent', () {
    expect(ZebraPrinterStatus.disconnected().batteryPercent, isNull);
  });

  test('toJson round-trips batteryPercent', () {
    final original = ZebraPrinterStatus.fromJson(baseJson(batteryPercent: 35));
    final again = ZebraPrinterStatus.fromJson(original.toJson());
    expect(again.batteryPercent, 35);
  });

  test('poll treats Not Connected and Not TCP as link loss', () {
    expect(
      interpretStatusPoll(rawText: 'Not Connected'),
      StatusPollDecision.linkLost,
    );
    expect(
      interpretStatusPoll(rawText: '  Not TCP  '),
      StatusPollDecision.linkLost,
    );
  });

  test('poll timeout and channel failure are link loss', () {
    expect(interpretStatusPoll(timedOut: true), StatusPollDecision.linkLost);
    expect(
      interpretStatusPoll(
          rawText: '{"isReadyToPrint":true}', channelFailed: true),
      StatusPollDecision.linkLost,
    );
  });

  test('poll JSON stays connected with or without battery', () {
    expect(
      interpretStatusPoll(
          rawText: '{"isReadyToPrint":true,"batteryPercent":40}'),
      StatusPollDecision.applyStatus,
    );
    expect(
      interpretStatusPoll(rawText: '{"isReadyToPrint":true}'),
      StatusPollDecision.applyStatus,
    );
  });

  test('poll ignores garbage that is not a dead-link token', () {
    expect(interpretStatusPoll(rawText: ''), StatusPollDecision.ignore);
    expect(interpretStatusPoll(rawText: 'null'), StatusPollDecision.ignore);
  });

  test('fromJson coerces numeric printMode without dropping batteryPercent',
      () {
    final json = baseJson(batteryPercent: 88);
    json['printMode'] = 2.0; // Swift/JSON number edge case
    final status = ZebraPrinterStatus.fromJson(json);
    expect(status.printMode, 2);
    expect(status.batteryPercent, 88);
  });
}
