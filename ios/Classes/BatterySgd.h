#import <Foundation/Foundation.h>
#import "ZebraPrinterConnection.h"

/// Link-OS SGD battery helpers. Returns nil when unknown or AC-powered.
@interface BatterySgd : NSObject

/// Reads battery percent over an open Link-OS connection (TCP or MFi BT).
/// Same connection typing as [SGD GET:withPrinterConnection:error:].
+ (NSNumber *_Nullable)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection;

@end
