 import Flutter
 import UIKit

 public class ArtemisZebraPlusPlugin: NSObject, FlutterPlugin {

   var printers = [Printer]()
   var binaryMessenger: FlutterBinaryMessenger?

   public static func register(with registrar: FlutterPluginRegistrar) {
     // Before any discover/connect. connectedAccessories is empty until this runs.
     Printer.registerForAccessoryNotifications()
     let channel = FlutterMethodChannel(name: "artemis_zebra_plus", binaryMessenger: registrar.messenger())
     let instance = ArtemisZebraPlusPlugin()
     instance.binaryMessenger = registrar.messenger()
     registrar.addMethodCallDelegate(instance, channel: channel)
   }

       public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
           switch call.method {
           case "getInstance":
               getInstance(result: result);
               break
           default:
               result("Unimplemented Method")
           }
       }

       public func getInstance( result: @escaping FlutterResult){
           let printer = Printer.getInstance(binaryMessenger: self.binaryMessenger!)
           printers.append(printer)
           result(printer.toString())
       }
 }
