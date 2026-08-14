#import <Foundation/Foundation.h>
#import "ZebraPrinterConnection.h"

/// Link-OS SGD battery helpers. Returns nil when unknown or AC-powered.
@interface BatterySgd : NSObject

+ (NSNumber *_Nullable)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection;

@end
