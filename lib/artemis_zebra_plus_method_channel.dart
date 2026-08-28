import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'artemis_zebra_plus_platform_interface.dart';
import 'zebra_logging.dart';
import 'zebra_printer.dart';

/// An implementation of [ArtemisZebraPlusPlatform] that uses method channels.
class MethodChannelArtemisZebraPlus extends ArtemisZebraPlusPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('artemis_zebra_plus');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<void> setMethodCallHandler({required Future<dynamic> Function(MethodCall call)? handler}) async {
    methodChannel.setMethodCallHandler(handler);
    // final result = await methodChannel.invokeMethod<String>('discoverPrinters');
    // return result;
  }


  @override
  Future<String?> discoverPrinters() async {

    final result = await methodChannel.invokeMethod<String>('discoverPrinters');
    return result;
  }

  @override
  Future<ZebraPrinter> getZebraPrinterInstance({String? label, required void Function(ZebraPrinter) notifier,Function? statusListener}) async {
    getPermissions();
    String id = await methodChannel.invokeMethod("getInstance");
    ZebraPrinter printer = ZebraPrinter(id, label: label, notifierFunction: notifier,statusListener: statusListener);
    zebraPackagePrint("${printer.instanceID}");

    return printer;
  }

  Future<void> getPermissions() async {
    // You can request multiple permissions at once.
    // if (await Permission.location.isGranted &&
    //     await Permission.bluetooth.isGranted &&
    //     Permission.bluetoothAdvertise.isGranted &&
    //     Permission.bluetoothConnect.isGranted &&
    //     Permission.bluetoothScan.isGranted) return;
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetooth,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.bluetoothScan,
    ].request();
    // print(statuses[Permission.location]);
    // print(statuses[Permission.bluetooth]);
    // print(statuses[Permission.bluetoothAdvertise]);
    // print(statuses[Permission.bluetoothConnect]);
    // print(statuses[Permission.bluetoothScan]);
  }
}
