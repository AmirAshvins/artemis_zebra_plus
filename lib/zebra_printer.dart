import 'dart:async';
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

  /// When true, the next native [connectionLost] is expected (user/app disconnect).
  bool _intentionalDisconnect = false;

  /// Serializes [printData] so shared BP+BT sessions do not interleave ZPL.
  Future<void> _printQueue = Future<void>.value();

  /// Monotonic poll tick for correlating skip/hang/success logs.
  int _batteryPollTick = 0;

  /// True while a battery poll invokeMethod is in flight (detect overlapping hangs).
  bool _batteryPollInFlight = false;

  ZebraPrinter(String id, {String? label, required void Function(ZebraPrinter) notifierFunction,Function? statusListener}) {
    channel = MethodChannel('ZebraPrinterInstance$id');
    log("ZebraPrinterInstanceCreated: $id  (${label ?? id})");
    instanceID = label == null ? id : "$id ($label)";
    notifier = notifierFunction;
    channel.setMethodCallHandler(_printerMethodCallHandler);
    broadcaster = statusListener;
    log('Zebra battery loop START [$instanceID] listener=${statusListener != null}');
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
      // Discovery must not leave the session stuck in discoveringPrinter forever —
      // that silently disables battery polls until a later connect.
      if (status == PrinterStatus.discoveringPrinter) {
        status = PrinterStatus.disconnected;
        log('Zebra discover done [$instanceID] → status=disconnected (ready for connect/poll)');
        notifier(this);
      }
      return result;
    }else{
      return "No Permission";
    }
  }

  @override
  Future<bool> connectToPrinter(String address) async {
    status = PrinterStatus.connecting;
    notifier(this);
    log('Zebra connect begin [$instanceID] address=$address');
    final bool result = await channel.invokeMethod("connectToPrinter", {"address": address});
    if (result) {
      print("result is true");
      status = PrinterStatus.ready;
      log("Zebra Instance $instanceID Connected to $address (status=$status, listener=${broadcaster != null})");
      notifier(this);
      // Fire-and-forget: do not block connect UI on SGD/status round-trip.
      log('Zebra post-connect poll scheduled [$instanceID]');
      unawaited(_pollPrinterStatusOnce(broadcaster, reason: 'post-connect'));
      return result;
    } else {
      print("result is false");
      status = PrinterStatus.disconnected;
      log('Zebra connect FAILED [$instanceID] address=$address');
      notifier(this);
      return result;
    }
  }

  @override
  Future<bool> printData(String data) {
    // Chain jobs so concurrent BP/BT prints on one MFi/TCP session stay ordered.
    final Future<bool> job = _printQueue.then((_) => _printDataImpl(data));
    _printQueue = job.then((_) {}, onError: (_) {});
    return job;
  }

  Future<bool> _printDataImpl(String data) async {
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
    _intentionalDisconnect = true;
    status = PrinterStatus.disconnecting;
    log('Zebra disconnect begin [$instanceID] intentional=true');
    notifier(this);
    try {
      final bool result = await channel.invokeMethod("disconnectPrinter");
      status = PrinterStatus.disconnected;
      notifier(this);
      log('Zebra disconnect end [$instanceID] result=$result');
      return result;
    } finally {
      // Native may also emit connectionLost; keep flag briefly for that handler.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        _intentionalDisconnect = false;
      });
    }
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
      final prev = status;
      status = PrinterStatus.disconnected;
      notifier(this);
      final zStatus = ZebraPrinterStatus.disconnected();
      zebraPrinterStatus = zStatus;
      broadcaster?.call(zStatus);
      if (_intentionalDisconnect) {
        log("printerDisconnected (intentional) [$instanceID] prevStatus=$prev");
        _intentionalDisconnect = false;
      } else {
        log("printerDisconnected (connectionLost) [$instanceID] prevStatus=$prev");
      }
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
  Future<void> _pollPrinterStatusOnce(Function? listener, {String reason = 'loop'}) async {
    final int tick = ++_batteryPollTick;
    final PrinterStatus statusSnapshot = status;
    // Avoid native SGD/status traffic while disconnected — it is slow and noisy.
    if (statusSnapshot != PrinterStatus.ready && statusSnapshot != PrinterStatus.printing) {
      log('Zebra battery poll SKIP [$instanceID] tick=$tick reason=$reason status=$statusSnapshot inFlight=$_batteryPollInFlight');
      return;
    }
    if (_batteryPollInFlight) {
      log('Zebra battery poll SKIP-OVERLAP [$instanceID] tick=$tick reason=$reason status=$statusSnapshot');
      return;
    }
    _batteryPollInFlight = true;
    final sw = Stopwatch()..start();
    log('Zebra battery poll ENTER [$instanceID] tick=$tick reason=$reason status=$statusSnapshot listener=${listener != null}');
    try {
      // Connected polls are SGD-only (battery); skip slow getCurrentStatus.
      // Hard timeout so a stuck native SGD cannot kill the 5s broadcast loop.
      final dynamic raw = await channel
          .invokeMethod('checkPrinterStatus', {'sgdOnly': true})
          .timeout(const Duration(seconds: 8));
      final String rawText = raw?.toString() ?? 'null';
      log('Zebra battery poll RAW [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} len=${rawText.length} head="${rawText.length > 180 ? rawText.substring(0, 180) : rawText}"');
      try {
        final parsed = ZebraPrinterStatus.fromJson(jsonDecode(rawText) as Map<String, dynamic>);
        zebraPrinterStatus = parsed;
        log('Zebra battery poll OK [$instanceID] tick=$tick batteryPercent=${parsed.batteryPercent} ready=${parsed.isReadyToPrint} callingListener=${listener != null}');
        listener?.call(parsed);
        log('Zebra battery poll LISTENER-DONE [$instanceID] tick=$tick');
      } catch (e) {
        log('Zebra battery poll PARSE-FAIL [$instanceID] tick=$tick raw="$rawText" error=$e');
      }
    } on TimeoutException catch (e) {
      log('Zebra battery poll TIMEOUT [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} error=$e — native SGD likely hung');
    } catch (e) {
      log('Zebra battery poll CHANNEL-FAIL [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} error=$e');
    } finally {
      _batteryPollInFlight = false;
      log('Zebra battery poll EXIT [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} statusNow=$status');
    }
  }

  /// Polls printer status (incl. SGD battery) every 5s and fans out to [listener].
  void broadCastStatus(Function? listener) {
    log('Zebra battery loop TICK [$instanceID] status=$status inFlight=$_batteryPollInFlight');
    _pollPrinterStatusOnce(listener, reason: 'loop').whenComplete(() {
      Future.delayed(const Duration(seconds: 5), () {
        broadCastStatus(listener);
      });
    });
  }
}
