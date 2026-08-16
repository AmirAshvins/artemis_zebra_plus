#import "BatterySgd.h"
#import "SGD.h"

@implementation BatterySgd

/// Returns YES when Link-OS reports line/AC/mains power (hide battery badge).
+ (BOOL)_isAcPowerSource:(NSString *)source {
    if (source == nil || source.length == 0) {
        return NO;
    }
    // Prefer exact / prefix matches — avoid bare containsString:@"AC" false positives.
    if ([source isEqualToString:@"AC"] ||
        [source isEqualToString:@"LINE"] ||
        [source isEqualToString:@"MAINS"]) {
        return YES;
    }
    if ([source hasPrefix:@"AC"] ||
        [source containsString:@"LINE"] ||
        [source containsString:@"MAINS"]) {
        return YES;
    }
    return NO;
}

/// Parses a 0–100 integer from an SGD percent string (optional trailing %).
+ (NSNumber *)_parsePercentString:(NSString *)raw {
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
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([trimmed rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return nil;
    }
    NSInteger n = [trimmed integerValue];
    if (n < 0 || n > 100) {
        return nil;
    }
    return @(n);
}

+ (NSNumber *)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection {
    @try {
        NSError *sourceError = nil;
        NSString *sourceRaw = [SGD GET:@"power.source" withPrinterConnection:connection error:&sourceError];
        if (sourceError != nil) {
            NSLog(@"[BatterySgd] power.source error: %@", sourceError.localizedDescription);
        }
        NSString *source = [[sourceRaw uppercaseString]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSLog(@"[BatterySgd] power.source raw='%@' normalized='%@'", sourceRaw, source);

        if ([self _isAcPowerSource:source]) {
            NSLog(@"[BatterySgd] skipping percent — AC/line/mains source '%@'", source);
            return nil;
        }

        NSError *percentError = nil;
        NSString *raw = [SGD GET:@"power.percent" withPrinterConnection:connection error:&percentError];
        if (percentError != nil) {
            NSLog(@"[BatterySgd] power.percent error: %@", percentError.localizedDescription);
        }
        NSLog(@"[BatterySgd] power.percent raw='%@'", raw);

        NSNumber *parsed = [self _parsePercentString:raw];
        // Older firmware sometimes exposes power.percentage instead.
        if (parsed == nil) {
            NSError *altError = nil;
            NSString *altRaw = [SGD GET:@"power.percentage" withPrinterConnection:connection error:&altError];
            if (altError != nil) {
                NSLog(@"[BatterySgd] power.percentage error: %@", altError.localizedDescription);
            }
            NSLog(@"[BatterySgd] power.percentage raw='%@'", altRaw);
            parsed = [self _parsePercentString:altRaw];
        }

        NSLog(@"[BatterySgd] parsed batteryPercent=%@", parsed);
        return parsed;
    } @catch (NSException *exception) {
        NSLog(@"[BatterySgd] exception: %@", exception);
        return nil;
    }
}

@end
