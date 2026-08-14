#import "BatterySgd.h"
#import "SGD.h"

@implementation BatterySgd

+ (NSNumber *)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection {
    @try {
        NSError *sourceError = nil;
        NSString *sourceRaw = [SGD GET:@"power.source" withPrinterConnection:connection error:&sourceError];
        NSString *source = [[sourceRaw uppercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([source containsString:@"LINE"] || [source containsString:@"AC"] || [source containsString:@"MAINS"]) {
            return nil;
        }
        NSError *percentError = nil;
        NSString *raw = [SGD GET:@"power.percent" withPrinterConnection:connection error:&percentError];
        if (raw == nil) {
            return nil;
        }
        NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ([trimmed hasSuffix:@"%"]) {
            trimmed = [[trimmed substringToIndex:trimmed.length - 1]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        }
        if (trimmed.length == 0) {
            return nil;
        }
        NSInteger n = [trimmed integerValue];
        // integerValue returns 0 for non-numeric; reject unless the string is actually 0.
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([trimmed rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
            return nil;
        }
        if (n < 0 || n > 100) {
            return nil;
        }
        return @(n);
    } @catch (NSException *exception) {
        return nil;
    }
}

@end
