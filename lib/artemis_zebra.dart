
import 'dart:developer';

import 'package:artemis_zebra_plus/artemis_zebra_plus_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'zebra_printer.dart';

class ArtemisZebraPlus {

  ArtemisZebraPlus(){
    ArtemisZebraPlusPlatform.instance.setMethodCallHandler(handler: _methodCallHandler);
  }
  Future<String?> getPlatformVersion() {
    return ArtemisZebraPlusPlatform.instance.getPlatformVersion();
  }

  Future<String?> discoverPrinters() {
    return ArtemisZebraPlusPlatform.instance.discoverPrinters();
  }

  Future<String?> setMethodCallHandler() {
    return ArtemisZebraPlusPlatform.instance.discoverPrinters();
  }

  static Future<ZebraPrinter> getPrinterInstance({String? label,required void Function(ZebraPrinter) notifier,Function? statusListener}) async {
    return ArtemisZebraPlusPlatform.instance.getZebraPrinterInstance(label:label,notifier:notifier,statusListener: statusListener);
  }
  static Future<void> getPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.nearbyWifiDevices,
      // Permission.storage,
    ].request();
    print("Persmissions: ${statuses[Permission.location]}");
  }

  Future<dynamic> _methodCallHandler(MethodCall methodCall) async {


    if (methodCall.method == "printerFound") {
      log("printerFound");
      // String barcode = methodCall.arguments.toString();

    }else if(methodCall.method == "discoveryDone"){
      log("discoveryDone");
      String? ocrJson = await methodCall.arguments;
      if (ocrJson == null) return null;
      try {
        // OcrData ocrData = OcrData.fromJson(jsonDecode(ocrJson));
        // if (widget.onOcrRead == null) {
        //   log("Text ${ocrData.text} Detected but no onOcrRead is not  Implemented");
        // } else {
        //   widget.onOcrRead!(ocrData);
        // }
      } catch (e) {
        return null;
      }
    }

  }


}


class ZebraPrinterStatus {
  final bool isPaused;
  final int numberOfFormatsInReceiveBuffer;
  final bool isReadyToPrint;
  final bool isPaperOut;
  final bool isPartialFormatInProgress;
  final bool isReceiveBufferFull;
  final int labelLengthInDots;
  final bool isRibbonOut;
  final bool isHeadTooHot;
  final int labelsRemainingInBatch;
  final bool isHeadOpen;
  final bool isHeadCold;
  final int printMode;

  /// Link-OS SGD `power.percent` (0–100). Null when unknown, AC-powered, or SGD failed.
  final int? batteryPercent;

  ZebraPrinterStatus({
    required this.isPaused,
    required this.numberOfFormatsInReceiveBuffer,
    required this.isReadyToPrint,
    required this.isPaperOut,
    required this.isPartialFormatInProgress,
    required this.isReceiveBufferFull,
    required this.labelLengthInDots,
    required this.isRibbonOut,
    required this.isHeadTooHot,
    required this.labelsRemainingInBatch,
    required this.isHeadOpen,
    required this.isHeadCold,
    required this.printMode,
    this.batteryPercent,
  });

  ZebraPrinterStatus copyWith({
    bool? isPaused,
    int? numberOfFormatsInReceiveBuffer,
    bool? isReadyToPrint,
    bool? isPaperOut,
    bool? isPartialFormatInProgress,
    bool? isReceiveBufferFull,
    int? labelLengthInDots,
    bool? isRibbonOut,
    bool? isHeadTooHot,
    int? labelsRemainingInBatch,
    bool? isHeadOpen,
    bool? isHeadCold,
    int? printMode,
    int? batteryPercent,
  }) =>
      ZebraPrinterStatus(
        isPaused: isPaused ?? this.isPaused,
        numberOfFormatsInReceiveBuffer: numberOfFormatsInReceiveBuffer ?? this.numberOfFormatsInReceiveBuffer,
        isReadyToPrint: isReadyToPrint ?? this.isReadyToPrint,
        isPaperOut: isPaperOut ?? this.isPaperOut,
        isPartialFormatInProgress: isPartialFormatInProgress ?? this.isPartialFormatInProgress,
        isReceiveBufferFull: isReceiveBufferFull ?? this.isReceiveBufferFull,
        labelLengthInDots: labelLengthInDots ?? this.labelLengthInDots,
        isRibbonOut: isRibbonOut ?? this.isRibbonOut,
        isHeadTooHot: isHeadTooHot ?? this.isHeadTooHot,
        labelsRemainingInBatch: labelsRemainingInBatch ?? this.labelsRemainingInBatch,
        isHeadOpen: isHeadOpen ?? this.isHeadOpen,
        isHeadCold: isHeadCold ?? this.isHeadCold,
        printMode: printMode ?? this.printMode,
        batteryPercent: batteryPercent ?? this.batteryPercent,
      );

  /// Parses SGD / JSON battery values. Missing, null, or unparseable → null (never fake 0).
  static int? parseBatteryPercent(dynamic value) {
    if (value == null) return null;
    String raw;
    if (value is int) {
      if (value < 0 || value > 100) return null;
      return value;
    }
    if (value is num) {
      final n = value.round();
      if (n < 0 || n > 100) return null;
      return n;
    }
    raw = value.toString().trim();
    if (raw.endsWith('%')) {
      raw = raw.substring(0, raw.length - 1).trim();
    }
    if (raw.isEmpty) return null;
    final n = int.tryParse(raw);
    if (n == null || n < 0 || n > 100) return null;
    return n;
  }

  factory ZebraPrinterStatus.fromJson(Map<String, dynamic> json) => ZebraPrinterStatus(
    isPaused: json["isPaused"] == true,
    numberOfFormatsInReceiveBuffer: _asInt(json["numberOfFormatsInReceiveBuffer"]) ?? 0,
    isReadyToPrint: json["isReadyToPrint"] == true,
    isPaperOut: json["isPaperOut"] == true,
    isPartialFormatInProgress: json["isPartialFormatInProgress"] == true,
    isReceiveBufferFull: json["isReceiveBufferFull"] == true,
    labelLengthInDots: _asInt(json["labelLengthInDots"]) ?? 0,
    isRibbonOut: json["isRibbonOut"] == true,
    isHeadTooHot: json["isHeadTooHot"] == true,
    labelsRemainingInBatch: _asInt(json["labelsRemainingInBatch"]) ?? 0,
    isHeadOpen: json["isHeadOpen"] == true,
    isHeadCold: json["isHeadCold"] == true,
    // Swift UInt32 / Android int must not blow the whole parse (and drop battery).
    printMode: _asInt(json["printMode"]) ?? 0,
    batteryPercent: parseBatteryPercent(json["batteryPercent"]),
  );

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  Map<String, dynamic> toJson() => {
    "isPaused": isPaused,
    "numberOfFormatsInReceiveBuffer": numberOfFormatsInReceiveBuffer,
    "isReadyToPrint": isReadyToPrint,
    "isPaperOut": isPaperOut,
    "isPartialFormatInProgress": isPartialFormatInProgress,
    "isReceiveBufferFull": isReceiveBufferFull,
    "labelLengthInDots": labelLengthInDots,
    "isRibbonOut": isRibbonOut,
    "isHeadTooHot": isHeadTooHot,
    "labelsRemainingInBatch": labelsRemainingInBatch,
    "isHeadOpen": isHeadOpen,
    "isHeadCold": isHeadCold,
    "printMode": printMode,
    "batteryPercent": batteryPercent,
  };


  @override
  String toString() {
    if(isReadyToPrint) return "Ready";
    if(isPaperOut) return "PaperOut";
    if(isReceiveBufferFull) return "Full";
    if(isRibbonOut) return "RibbonOut";
    if(isHeadTooHot) return "Hot";
    if(isHeadCold) return "Cold";
    if(isHeadOpen) return "Open";
    if(isReadyToPrint) return "Ready";

    return "Unknown";
  }


  factory ZebraPrinterStatus.disconnected() => ZebraPrinterStatus(
    isPaused: false,
    numberOfFormatsInReceiveBuffer: 0,
    isReadyToPrint: false,
    isPaperOut: false,
    isPartialFormatInProgress: false,
    isReceiveBufferFull: false,
    labelLengthInDots: 0,
    isRibbonOut: false,
    isHeadTooHot: false,
    labelsRemainingInBatch: 0,
    isHeadOpen: false,
    isHeadCold: false,
    printMode: 0,
    batteryPercent: null,
  );
}