import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'artemis_zebra.dart';
import 'zebra_link_status.dart';
import 'zebra_logging.dart';
import 'zebra_printer_interface.dart';

class ZebraPrinter implements ArtemisZebraPrinterInterface {
  late MethodChannel channel;
  late String instanceID;
  late Function? broadcaster;

  late void Function(ZebraPrinter) notifier;

  /// When true, the next native [connectionLost] is expected (user/app disconnect).
  bool _intentionalDisconnect = false;

  /// Bumps on every connect attempt so stale [connectionLost] cannot wipe a new session.
  int _sessionEpoch = 0;

  /// Serializes [printData] so shared BP+BT sessions do not interleave ZPL.
  Future<void> _printQueue = Future<void>.value();

  /// Monotonic poll tick for correlating skip/hang/success logs.
  int _batteryPollTick = 0;

  /// True while a battery poll invokeMethod is in flight (detect overlapping hangs).
  bool _batteryPollInFlight = false;

  /// When false, the 5s SGD timer is cancelled (disconnect / dispose / background).
  bool _statusPollingEnabled = false;

  Timer? _statusPollTimer;

  ZebraPrinter(String id,
      {String? label,
      required void Function(ZebraPrinter) notifierFunction,
      Function? statusListener}) {
    channel = MethodChannel('ZebraPrinterInstance$id');
    zebraPackageLog("ZebraPrinterInstanceCreated: $id  (${label ?? id})");
    instanceID = label == null ? id : "$id ($label)";
    notifier = notifierFunction;
    channel.setMethodCallHandler(_printerMethodCallHandler);
    broadcaster = statusListener;
  }

  PrinterStatus status = PrinterStatus.disconnected;
  bool isRotated = false;
  List<FoundPrinter> foundPrinters = [];

  ZebraPrinterStatus? zebraPrinterStatus;

  @override
  checkPermissions() async {
    return true;
    if (Platform.isIOS) return true;
    bool result = await channel.invokeMethod("checkPermissions");
    return result;
  }

  @override
  discoverPrinters() async {
    bool permissions = await checkPermissions();
    if (permissions) {
      if (status != PrinterStatus.ready) {
        status = PrinterStatus.discoveringPrinter;
        notifier(this);
      }

      String result = await channel.invokeMethod("discoverPrinters");
      // Discovery must not leave the session stuck in discoveringPrinter forever —
      // that silently disables battery polls until a later connect.
      if (status == PrinterStatus.discoveringPrinter) {
        status = PrinterStatus.disconnected;
        zebraPackageLog(
            'Zebra discover done [$instanceID] → status=disconnected (ready for connect/poll)');
        notifier(this);
      }
      return result;
    } else {
      return "No Permission";
    }
  }

  @override
  Future<bool> connectToPrinter(String address) async {
    final int epoch = ++_sessionEpoch;
    status = PrinterStatus.connecting;
    notifier(this);
    zebraPackageLog(
        'Zebra connect begin [$instanceID] address=$address epoch=$epoch');
    final bool result =
        await channel.invokeMethod("connectToPrinter", {"address": address});
    // A newer connect/disconnect superseded this attempt.
    if (epoch != _sessionEpoch) {
      zebraPackageLog(
          'Zebra connect STALE [$instanceID] epoch=$epoch now=$_sessionEpoch result=$result — ignoring');
      return false;
    }
    if (result) {
      zebraPackagePrint("result is true");
      status = PrinterStatus.ready;
      zebraPackageLog(
          "Zebra Instance $instanceID Connected to $address (status=$status, epoch=$epoch, listener=${broadcaster != null})");
      notifier(this);
      // Fire-and-forget: do not block connect UI on SGD/status round-trip.
      zebraPackageLog(
          'Zebra post-connect poll scheduled [$instanceID] epoch=$epoch');
      unawaited(_pollPrinterStatusOnce(broadcaster, reason: 'post-connect'));
      startStatusPolling();
      return result;
    } else {
      zebraPackagePrint("result is false");
      status = PrinterStatus.disconnected;
      zebraPackageLog(
          'Zebra connect FAILED [$instanceID] address=$address epoch=$epoch');
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
      zebraPackageLog("Zebra Instance $instanceID Print Done");
    } else {
      status = PrinterStatus.disconnected;
    }
    notifier(this);
    return result;
  }

  @override
  Future<bool> disconnectPrinter() async {
    // Already down — skip native close so we do not queue a late connectionLost
    // that would wipe a subsequent connectToPrinter.
    if (status == PrinterStatus.disconnected ||
        status == PrinterStatus.disconnecting) {
      zebraPackageLog(
          'Zebra disconnect SKIP [$instanceID] already status=$status');
      stopStatusPolling();
      return true;
    }
    stopStatusPolling();
    _intentionalDisconnect = true;
    final int epochAtDisconnect = _sessionEpoch;
    status = PrinterStatus.disconnecting;
    zebraPackageLog(
        'Zebra disconnect begin [$instanceID] intentional=true epoch=$epochAtDisconnect');
    notifier(this);
    try {
      final bool result = await channel.invokeMethod("disconnectPrinter");
      // Only mark disconnected if no newer connect started meanwhile.
      if (epochAtDisconnect == _sessionEpoch) {
        status = PrinterStatus.disconnected;
        notifier(this);
      } else {
        zebraPackageLog(
            'Zebra disconnect end STALE [$instanceID] epoch=$epochAtDisconnect now=$_sessionEpoch — not wiping newer session');
      }
      zebraPackageLog(
          'Zebra disconnect end [$instanceID] result=$result statusNow=$status');
      return result;
    } finally {
      // Native may also emit connectionLost; keep flag briefly for that handler.
      Future<void>.delayed(const Duration(milliseconds: 800), () {
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
        zebraPackageLog(pJson);
        FoundPrinter foundPrinter = FoundPrinter.fromJson(jsonDecode(pJson));
        zebraPackageLog("printerFound : ${foundPrinter.toString()}");
        if (!foundPrinters
            .any((element) => element.address == foundPrinter.address)) {
          foundPrinters.add(foundPrinter);
        }
        notifier(this);
      } catch (e) {
        zebraPackageLog("Parsing Printer Failed $e");
        return null;
      }
    } else if (methodCall.method == "discoveryDone") {
      zebraPackageLog("discoveryDone");
    } else if (methodCall.method == "discoveryError") {
      String? error = await methodCall.arguments["error"];
      zebraPackageLog("discoveryError : $error");
    } else if (methodCall.method == "connectionLost") {
      final prev = status;
      if (_intentionalDisconnect) {
        _intentionalDisconnect = false;
        // Intentional close raced with a new connect — do not wipe ready/connecting.
        if (prev == PrinterStatus.connecting ||
            prev == PrinterStatus.ready ||
            prev == PrinterStatus.printing) {
          zebraPackageLog(
            'printerDisconnected (intentional STALE ignored) [$instanceID] prevStatus=$prev epoch=$_sessionEpoch',
          );
          return null;
        }
        _markLinkLost('intentional');
        return null;
      }
      // Unexpected drop during connect belongs to the previous socket.
      if (prev == PrinterStatus.connecting) {
        zebraPackageLog(
          'printerDisconnected (connectionLost during connecting — keeping connecting) [$instanceID]',
        );
        return null;
      }
      _markLinkLost('connectionLost');
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

    zebraPackageLog("Setting => $command");
    status = PrinterStatus.printing;
    notifier(this);
    await Future.delayed(const Duration(milliseconds: 300));
    await channel.invokeMethod("printData", {"data": command});
    status = PrinterStatus.ready;
    notifier(this);
  }

  @override
  Future<String> checkPrinterStatus() async {
    return await channel.invokeMethod("checkPrinterStatus");
  }

  @override
  Future<String> sendZplOverTcp() async {
    return await channel.invokeMethod("sendZplOverTcp");
  }

  @override
  Future<String> sendCpclOverTcp() async {
    return await channel.invokeMethod("sendCpclOverTcp");
  }

  @override
  Future<String> sampleWithGCD() async {
    return await channel.invokeMethod("sampleWithGCD");
  }

  /// Marks the session down and publishes disconnected chrome before listeners run.
  ///
  /// Ignored while [PrinterStatus.connecting] so a late drop from the previous
  /// socket cannot cancel an in-flight connect. Already-disconnected is a no-op
  /// so ACL and the poll can both report the same drop.
  void _markLinkLost(String reason) {
    if (status == PrinterStatus.disconnected) {
      stopStatusPolling();
      return;
    }
    if (status == PrinterStatus.connecting) {
      zebraPackageLog(
        'printerDisconnected ignored ($reason) [$instanceID] status=connecting epoch=$_sessionEpoch',
      );
      return;
    }
    status = PrinterStatus.disconnected;
    final zStatus = ZebraPrinterStatus.disconnected();
    zebraPrinterStatus = zStatus;
    zebraPackageLog(
      'printerDisconnected ($reason) [$instanceID] epoch=$_sessionEpoch',
    );
    notifier(this);
    broadcaster?.call(zStatus);
    stopStatusPolling();
  }

  /// Applies link loss only if this poll still belongs to the ready session.
  ///
  /// A connect bumps [_sessionEpoch]. A late "Not Connected" from the previous
  /// poll must not tear down the new session.
  void _dropLinkIfSameSession(int epoch, String reason) {
    if (epoch != _sessionEpoch || status != PrinterStatus.ready) {
      zebraPackageLog(
        'printerDisconnected STALE ($reason) [$instanceID] epoch=$epoch now=$_sessionEpoch status=$status',
      );
      return;
    }
    _markLinkLost(reason);
  }

  /// One status/SGD poll: updates [zebraPrinterStatus], notifies [listener], and logs battery %.
  ///
  /// Runs only while [status] is [PrinterStatus.ready]. A print holds the port,
  /// so a failed SGD read during [PrinterStatus.printing] must not look like
  /// power-off — the print write already disconnects when the socket throws.
  Future<void> _pollPrinterStatusOnce(
    Function? listener, {
    String reason = 'loop',
  }) async {
    final int tick = ++_batteryPollTick;
    final int epochAtPoll = _sessionEpoch;
    final PrinterStatus statusSnapshot = status;
    if (statusSnapshot != PrinterStatus.ready) {
      zebraPackageLog(
        'Zebra battery poll SKIP [$instanceID] tick=$tick reason=$reason status=$statusSnapshot inFlight=$_batteryPollInFlight',
      );
      return;
    }
    if (_batteryPollInFlight) {
      zebraPackageLog(
        'Zebra battery poll SKIP-OVERLAP [$instanceID] tick=$tick reason=$reason status=$statusSnapshot',
      );
      return;
    }
    _batteryPollInFlight = true;
    final sw = Stopwatch()..start();
    zebraPackageLog(
      'Zebra battery poll ENTER [$instanceID] tick=$tick reason=$reason status=$statusSnapshot listener=${listener != null}',
    );
    try {
      // Connected polls are SGD-only (battery); skip slow getCurrentStatus.
      // Hard timeout so a stuck native SGD cannot leave the session looking ready.
      final dynamic raw = await channel.invokeMethod('checkPrinterStatus',
          {'sgdOnly': true}).timeout(const Duration(seconds: 8));
      final String rawText = raw?.toString() ?? '';
      zebraPackageLog(
        'Zebra battery poll RAW [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} len=${rawText.length} head="${rawText.length > 180 ? rawText.substring(0, 180) : rawText}"',
      );
      final decision = interpretStatusPoll(rawText: rawText);
      if (decision == StatusPollDecision.linkLost) {
        _dropLinkIfSameSession(epochAtPoll, 'poll:$rawText');
        return;
      }
      if (decision != StatusPollDecision.applyStatus) {
        zebraPackageLog(
          'Zebra battery poll IGNORE [$instanceID] tick=$tick raw="$rawText"',
        );
        return;
      }
      try {
        final parsed = ZebraPrinterStatus.fromJson(
          jsonDecode(rawText) as Map<String, dynamic>,
        );
        // A newer connect or an earlier connectionLost owns the session now.
        if (epochAtPoll != _sessionEpoch || status != PrinterStatus.ready) {
          zebraPackageLog(
            'Zebra battery poll STALE [$instanceID] tick=$tick epoch=$epochAtPoll now=$_sessionEpoch status=$status',
          );
          return;
        }
        zebraPrinterStatus = parsed;
        zebraPackageLog(
          'Zebra battery poll OK [$instanceID] tick=$tick batteryPercent=${parsed.batteryPercent} ready=${parsed.isReadyToPrint} callingListener=${listener != null}',
        );
        listener?.call(parsed);
        zebraPackageLog(
          'Zebra battery poll LISTENER-DONE [$instanceID] tick=$tick',
        );
      } catch (e) {
        zebraPackageLog(
          'Zebra battery poll PARSE-FAIL [$instanceID] tick=$tick raw="$rawText" error=$e',
        );
      }
    } on TimeoutException catch (e) {
      zebraPackageLog(
        'Zebra battery poll TIMEOUT [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} error=$e — native SGD likely hung',
      );
      _dropLinkIfSameSession(epochAtPoll, 'poll-timeout');
    } catch (e) {
      zebraPackageLog(
        'Zebra battery poll CHANNEL-FAIL [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} error=$e',
      );
      _dropLinkIfSameSession(epochAtPoll, 'poll-channel');
    } finally {
      _batteryPollInFlight = false;
      zebraPackageLog(
        'Zebra battery poll EXIT [$instanceID] tick=$tick ms=${sw.elapsedMilliseconds} statusNow=$status',
      );
    }
  }

  /// Starts a 5s SGD battery poll. No-op when already running or disconnected.
  ///
  /// Five seconds plus the 8s hang timeout stays under a 15s detection cap
  /// when the OS never posts a disconnect event.
  void startStatusPolling() {
    if (_statusPollingEnabled) return;
    _statusPollingEnabled = true;
    zebraPackageLog(
        'Zebra battery loop START [$instanceID] listener=${broadcaster != null}');
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_statusPollingEnabled) return;
      unawaited(_pollPrinterStatusOnce(broadcaster, reason: 'loop'));
    });
  }

  /// Cancels the SGD poll timer (disconnect, dispose, or app background).
  void stopStatusPolling() {
    if (!_statusPollingEnabled && _statusPollTimer == null) return;
    _statusPollingEnabled = false;
    _statusPollTimer?.cancel();
    _statusPollTimer = null;
    zebraPackageLog('Zebra battery loop STOP [$instanceID]');
  }

  /// Releases the method channel and stops polling.
  void dispose() {
    stopStatusPolling();
    channel.setMethodCallHandler(null);
  }

  /// Polls printer status (incl. SGD battery) every 5s and fans out to [listener].
  ///
  /// Kept for callers that still invoke the old loop; prefer [startStatusPolling].
  void broadCastStatus(Function? listener) {
    broadcaster = listener ?? broadcaster;
    startStatusPolling();
  }
}
