import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/services.dart';

import 'artemis_zebra.dart';
import 'zebra_printer_interface.dart';

class ZebraPrinter implements ArtemisZebraPrinterInterface {
  late MethodChannel channel;
  late String instanceID;
  late Function? broadcaster;

  late void Function(ZebraPrinter) notifier;

  ZebraPrinter(String id, {String? label, required void Function(ZebraPrinter) notifierFunction,Function? statusListener}) {
    channel = MethodChannel('ZebraPrinterInstance$id');
    log("ZebraPrinterInstanceCreated: $id  (${label ?? id})");
    instanceID = label == null ? id : "$id ($label)";
    notifier = notifierFunction;
    channel.setMethodCallHandler(_printerMethodCallHandler);
    broadcaster = statusListener;
    broadCastStatus(statusListener);
  }

  PrinterStatus status = PrinterStatus.disconnected;
  bool isRotated = false;
  List<FoundPrinter> foundPrinters = [];

  ZebraPrinterStatus? zebraPrinterStatus;

  @override
  checkPermissions() async {
    return true;
    if(Platform.isIOS) return true;
    bool result = await channel.invokeMethod("checkPermissions");
    return result;
  }

  @override
  discoverPrinters() async {
    bool permissions = await checkPermissions();
    if (permissions) {
      if(status != PrinterStatus.ready){
        status = PrinterStatus.discoveringPrinter;
        notifier(this);
      }

      String result = await channel.invokeMethod("discoverPrinters");
      // status = PrinterStatus.disconnected;
      // notifier(this);
      return result;
    }else{
      return "No Permission";
    }
  }

  @override
  Future<bool> connectToPrinter(String address) async {
    status = PrinterStatus.connecting;
    notifier(this);
    final bool result = await channel.invokeMethod("connectToPrinter", {"address": address});
    if (result) {
      print("result is true");
      status = PrinterStatus.ready;
      log("Zebra Instance $instanceID Connected to $address");
      notifier(this);
      // Don't wait for the next 5s poll — push SGD battery/status immediately.
      await _pollPrinterStatusOnce(broadcaster);
      return result;
    } else {
      print("result is false");
      status = PrinterStatus.disconnected;
      notifier(this);
      return result;
    }
  }

  @override
  Future<bool> printData(String data) async {
    status = PrinterStatus.printing;
    notifier(this);

    if (!data.contains("^PON")) data = data.replaceAll("^XA", "^XA^PON");
    if (isRotated) {
      data = data.replaceAll("^PON", "^POI");
    }

    final bool result = await channel.invokeMethod("printData", {"data": data});
    if (result) {
      status = PrinterStatus.ready;
      log("Zebra Instance $instanceID Print Done");
    } else {
      status = PrinterStatus.disconnected;
    }
    notifier(this);
    return result;
  }

  @override
  Future<bool> disconnectPrinter() async {
    status = PrinterStatus.disconnecting;
    notifier(this);
    final bool result = await channel.invokeMethod("disconnectPrinter");
    status = PrinterStatus.disconnected;
    notifier(this);
    return result;
  }

  @override
  Future<bool> isPrinterConnected() async {
    final bool result = await channel.invokeMethod("isPrinterConnected");
    if (!result) {
      status = PrinterStatus.disconnected;
      notifier(this);
    }
    return result;
  }

  Future<dynamic> _printerMethodCallHandler(MethodCall methodCall) async {
    if (methodCall.method == "printerFound") {

      String? pJson = await methodCall.arguments;
      if (pJson == null) return null;
      try {
        log(pJson);
        FoundPrinter foundPrinter = FoundPrinter.fromJson(jsonDecode(pJson));
        log("printerFound : ${foundPrinter.toString()}");
        if(!foundPrinters.any((element) => element.address==foundPrinter.address)) {
          foundPrinters.add(foundPrinter);
        }
        notifier(this);
      } catch (e) {
        log("Parsing Printer Failed $e");
        return null;
      }
    } else if (methodCall.method == "discoveryDone") {
      log("discoveryDone");
    } else if (methodCall.method == "discoveryError") {
      String? error = await methodCall.arguments["error"];
      log("discoveryError : $error");
    } else if (methodCall.method == "connectionLost") {
      status = PrinterStatus.disconnected;
      notifier(this);
      final zStatus = ZebraPrinterStatus.disconnected();
      zebraPrinterStatus = zStatus;
      broadcaster?.call(zStatus);
      log("printerDisconnected");
    }
  }

  Future<dynamic> setSettings(Command setting, dynamic values) async {
    String command = "";
    switch (setting) {
      case Command.mediaType:
        if (values == MediaType.blackMark) {
          command = '''
          ! U1 setvar "media.type" "label"
          ! U1 setvar "media.sense_mode" "bar"
          ''';
        } else if (values == MediaType.journal) {
          command = '''
          ! U1 setvar "media.type" "journal"
          ''';
        } else if (values == MediaType.label) {
          command = '''
          ! U1 setvar "media.type" "label"
           ! U1 setvar "media.sense_mode" "gap"
          ''';
        }

        break;
      case Command.calibrate:
        command = '''~jc^xa^jus^xz''';
        break;
      case Command.darkness:
        command = '''! U1 setvar "print.tone" "$values"''';
        break;
    }

    if (setting == Command.calibrate) {
      command = '''~jc^xa^jus^xz''';
    }

      log("Setting => $command");
      status = PrinterStatus.printing;
      notifier(this);
      await Future.delayed(const Duration(milliseconds: 300));
      await channel.invokeMethod("printData", {"data": command});
      status = PrinterStatus.ready;
      notifier(this);

  }

 @override
  Future<String> checkPrinterStatus()async {
    return await channel.invokeMethod("checkPrinterStatus");
  }
  @override
  Future<String> sendZplOverTcp()async {
    return await channel.invokeMethod("sendZplOverTcp");
  }
  @override
  Future<String> sendCpclOverTcp()async {
    return await channel.invokeMethod("sendCpclOverTcp");
  }
  @override
  Future<String> sampleWithGCD()async {
    return await channel.invokeMethod("sampleWithGCD");
  }

  /// One status/SGD poll: updates [zebraPrinterStatus], notifies [listener], and logs battery %.
  Future<void> _pollPrinterStatusOnce(Function? listener) async {
    try {
      final dynamic raw = await channel.invokeMethod('checkPrinterStatus');
      final String rawText = raw?.toString() ?? 'null';
      try {
        final parsed = ZebraPrinterStatus.fromJson(jsonDecode(rawText) as Map<String, dynamic>);
        zebraPrinterStatus = parsed;
        listener?.call(parsed);
        log('Zebra battery poll [$instanceID]: batteryPercent=${parsed.batteryPercent}');
      } catch (e) {
        log('Zebra battery poll [$instanceID]: parse/status failed raw="$rawText" error=$e');
      }
    } catch (e) {
      log('Zebra battery poll [$instanceID]: channel failed error=$e');
    }
  }

  /// Polls printer status (incl. SGD battery) every 5s and fans out to [listener].
  void broadCastStatus(Function? listener) {
    _pollPrinterStatusOnce(listener).whenComplete(() {
      Future.delayed(const Duration(seconds: 5), () {
        broadCastStatus(listener);
      });
    });
  }
}
