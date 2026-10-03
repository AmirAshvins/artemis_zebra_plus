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

@end
