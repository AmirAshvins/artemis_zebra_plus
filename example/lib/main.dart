import 'dart:async';

import 'package:artemis_zebra_plus/artemis_zebra.dart';
import 'package:artemis_zebra_plus/zebra_printer.dart';
import 'package:artemis_zebra_plus/zebra_printer_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  String _platformVersion = 'Unknown';
  final _artemisZebraUtilPlugin = ArtemisZebraPlus();
  late ZebraPrinter printer;
  List<ZebraPrinter> printers = [];
  ZebraPrinterStatus? status;

  @override
  void initState() {
    super.initState();
    initPlatformState();
  }

  // Platform messages are asynchronous, so we initialize in an async method.
  Future<void> initPlatformState() async {
    String platformVersion;
    // Platform messages may fail, so we use a try/catch PlatformException.
    // We also handle the message potentially returning null.
    try {
      printer = await ArtemisZebraPlus.getPrinterInstance(notifier: (_) => setState(() {}));
    } on PlatformException {
      platformVersion = 'Failed to get platform version.';
    }

    // If the widget was removed from the tree while the asynchronous platform
    // message was in flight, we want to discard the reply rather than calling
    // setState to update our non-existent appearance.
    if (!mounted) return;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            ZebraPrinter p = await ArtemisZebraPlus.getPrinterInstance(
              label: "BP TEST",
              notifier: (p) {
                print("Notifier called ${p.status.name}");
                setState(() {});
              },
              statusListener: (ZebraPrinterStatus s) {
                status = s;
                setState(() {});
              },
            );
            printers.add(p);
            setState(() {});
            // ArtemisZebraPlus().getPlatformVersion().then((value){
            //   print(value);
            // });
          },
        ),
        appBar: AppBar(title: const Text('Plugin example app')),
        body: Column(
          children: [
            TextButton(
              onPressed: () {
                getPermissions();
              },
              child: const Text("Get Permissions"),
            ),
            ...printers
                .map(
                  (e) => Column(
                    children: [
                      ListTile(
                        onTap: () {
                          e.isPrinterConnected();
                        },
                        onLongPress: () {
                          e.disconnectPrinter();
                        },
                        leading: Icon(Icons.print, color: e.status.color),
                        subtitle: Text("${e.instanceID} :${e.status.label}"),
                        // trailing: Text(""),
                        title: Row(
                          children: [
                            TextButton(
                              onPressed: () {
                                e.discoverPrinters().then((value) {
                                  print(value);
                                });
                              },
                              child: const Text("Find"),
                            ),
                            TextButton(
                              onPressed: () {
                                // e.connectToPrinter("192.168.1.8");
                                // e.disconnectPrinter();
                                if (e.status == PrinterStatus.disconnected) {
                                  if (e.foundPrinters.isEmpty) {
                                    e.connectToPrinter('192.168.45.151');
                                  } else {
                                    if (printers.indexOf(e) != 0) {
                                      e.connectToPrinter(e.foundPrinters.last.address);
                                    } else {
                                      e.connectToPrinter(e.foundPrinters.first.address);
                                    }
                                  }
                                } else {
                                  e.disconnectPrinter();
                                }
                              },
                              child: const Text("Connect"),
                            ),
                            TextButton(
                              onPressed: () {
                                e.printData('''
                    ^XA

^FX Top section with logo, name and address.
^CF0,60
^FO50,50^GB100,100,100^FS
^FO75,75^FR^GB100,100,100^FS
^FO93,93^GB40,40,40^FS
^FO220,50^FDIntershipping, Inc.^FS
^CF0,30
^FO220,115^FD1000 Shipping Lane^FS
^FO220,155^FDShelbyville TN 38102^FS
^FO220,195^FDUnited States (USA)^FS
^FO50,250^GB700,3,3^FS

^FX Second section with recipient address and permit information.
^CFA,30
^FO50,300^FDJohn Doe^FS
^FO50,340^FD100 Main Street^FS
^FO50,380^FDSpringfield TN 39021^FS
^FO50,420^FDUnited States (USA)^FS
^CFA,15
^FO600,300^GB150,150,3^FS
^FO638,340^FDPermit^FS
^FO638,390^FD123456^FS
^FO50,500^GB700,3,3^FS

^FX Third section with bar code.
^BY5,2,270
^FO100,550^BC^FD12345678^FS

^FX Fourth section (the two boxes on the bottom).
^FO50,900^GB700,250,3^FS
^FO400,900^GB3,250,3^FS
^CF0,40
^FO100,960^FDCtr. X34B-1^FS
^FO100,1010^FDREF1 F00B47^FS
^FO100,1060^FDREF2 BL4H8^FS
^CF0,190
^FO470,955^FDCA^FS

^XZ
                    ''');
                              },
                              child: const Text("Print"),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () async {
                              await e.setSettings(Command.mediaType, MediaType.label);

                              // await e.setSettings(Command.mediaType, MediaType.journal);
                              // await e.setSettings(Command.mediaType, MediaType.label);
                              // await e.setSettings(Command.mediaType, MediaType.journal);
                            },
                            child: const Text("Label"),
                          ),
                          TextButton(
                            onPressed: () async {
                              await e.setSettings(Command.mediaType, MediaType.journal);

                              // await e.setSettings(Command.mediaType, MediaType.journal);
                              // await e.setSettings(Command.mediaType, MediaType.label);
                              // await e.setSettings(Command.mediaType, MediaType.journal);
                            },
                            child: const Text("Journal"),
                          ),
                          TextButton(
                            onPressed: () async {
                              await e.setSettings(Command.mediaType, MediaType.blackMark);

                              // await e.setSettings(Command.mediaType, MediaType.journal);
                              // await e.setSettings(Command.mediaType, MediaType.label);
                              // await e.setSettings(Command.mediaType, MediaType.journal);
                            },
                            child: const Text("Black"),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: () async {
                              await e.checkPrinterStatus();
                            },
                            child: const Text("Check Status"),
                          ),
                          TextButton(
                            onPressed: () async {
                              await e.sendZplOverTcp();
                            },
                            child: const Text("Zpl"),
                          ),
                          TextButton(
                            onPressed: () async {
                              await e.sendCpclOverTcp();
                            },
                            child: const Text("Cpcl"),
                          ),
                          TextButton(
                            onPressed: () async {
                              await e.sampleWithGCD();
                            },
                            child: const Text("GCD"),
                          ),
                        ],
                      ),
                      Text(status?.toString() ?? '--'),
                      Column(
                        children: e.foundPrinters
                            .map(
                              (a) => TextButton(
                                onPressed: () {
                                  e.connectToPrinter(a.address);
                                },
                                child: Text("${a.name} ${a.address}"),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                )
                .toList(),
          ],
        ),
      ),
    );
  }

  void getPermissions() {
    ArtemisZebraPlus.getPermissions();
  }
}
