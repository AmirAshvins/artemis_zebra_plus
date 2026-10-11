#import <Foundation/Foundation.h>
#import "ZebraPrinterConnection.h"

/// Link-OS SGD battery helpers.
@interface BatterySgd : NSObject

/// Reads battery percent over an open Link-OS connection.
///
/// [linkFailed] is set to YES only when the transport errors and no SGD scalar
/// comes back (printer powered off or out of range). A nil percent with
/// linkFailed NO means AC power or an unknown key — the link is still up.
+ (NSNumber *_Nullable)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection
                                         linkFailed:(BOOL *_Nullable)linkFailed;

/// Reads battery percent. Nil when unknown or AC-powered. Link errors are ignored.
+ (NSNumber *_Nullable)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection;

/// Turns off Bluetooth sniff mode once, then resets the printer so it sticks.
///
/// Newer iPhones drop this radio about every 60 seconds while the setting is
/// "enabled" (Zebra article 000021307). No-op when it is already "disabled"
/// or the value cannot be read. The reset drops the link that just opened.
+ (void)disableBluetoothSniffModeIfNeeded:(id<ZebraPrinterConnection, NSObject>)connection;

@end
