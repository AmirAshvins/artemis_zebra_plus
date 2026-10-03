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

/// Rejects leftover ~HS / status blobs that SGD.GET sometimes returns after getCurrentStatus.
+ (BOOL)_looksLikeValidSgdScalar:(NSString *)raw {
    if (raw == nil) {
        return NO;
    }
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0 || trimmed.length > 64) {
        return NO;
    }
    // Host-status style payloads use STX/ETX (^B/^C) framing.
    if ([trimmed rangeOfString:@"^B"].location != NSNotFound ||
        [trimmed rangeOfString:@"^C"].location != NSNotFound ||
        [trimmed rangeOfString:@"\x02"].location != NSNotFound ||
        [trimmed rangeOfString:@"\x03"].location != NSNotFound) {
        return NO;
    }
    // Multi-line blobs are never valid power.* scalars.
    if ([trimmed rangeOfString:@"\n"].location != NSNotFound) {
        return NO;
    }
    return YES;
}

/// Parses a leading 0–100 integer from SGD strings like "91", "91%", "91% Full".
+ (NSNumber *)_parsePercentString:(NSString *)raw {
    if (![self _looksLikeValidSgdScalar:raw]) {
        NSLog(@"[BatterySgd] reject scalar raw='%@'", raw);
        return nil;
    }
    NSString *trimmed = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Take the first contiguous digit run (handles "91% Full", "100 %", etc.).
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSUInteger start = NSNotFound;
    NSUInteger end = trimmed.length;
    for (NSUInteger i = 0; i < trimmed.length; i++) {
        unichar c = [trimmed characterAtIndex:i];
        if ([digits characterIsMember:c]) {
            if (start == NSNotFound) {
                start = i;
            }
        } else if (start != NSNotFound) {
            end = i;
            break;
        }
    }
    if (start == NSNotFound) {
        return nil;
    }
    NSString *numStr = [trimmed substringWithRange:NSMakeRange(start, end - start)];
    NSInteger n = [numStr integerValue];
    if (n < 0 || n > 100) {
        return nil;
    }
    return @(n);
}

/// Best-effort single drain. Do NOT loop — connection read: can block for maxTimeoutForRead.
+ (void)_drainConnectionOnce:(id<ZebraPrinterConnection, NSObject>)connection {
    @try {
        BOOL available = [connection hasBytesAvailable];
        NSLog(@"[BatterySgd] drain check hasBytesAvailable=%@", available ? @"YES" : @"NO");
        if (!available) {
            return;
        }
        NSError *readError = nil;
        NSData *data = [connection read:&readError];
        NSLog(@"[BatterySgd] drained bytes=%lu error=%@",
              (unsigned long)(data.length),
              readError.localizedDescription ?: @"nil");
    } @catch (NSException *exception) {
        NSLog(@"[BatterySgd] drain exception: %@", exception);
    }
}

/// Short-timeout SGD GET so a stuck radio cannot hang the Dart poll loop.
+ (NSString *)_getVar:(NSString *)key
       connection:(id<ZebraPrinterConnection, NSObject>)connection
            error:(NSError **)error {
    // 2s first byte, 200ms quiet — enough for BT SGD, short enough to recover.
    return [SGD GET:key
withPrinterConnection:connection
withMaxTimeoutForRead:2000
andWithTimeToWaitForMoreData:200
                error:error];
}

/// Tries Link-OS charge SGD keys in preference order; returns first parseable value.
+ (NSNumber *)_readChargePercent:(id<ZebraPrinterConnection, NSObject>)connection {
    NSArray<NSString *> *keys = @[
        @"power.percent_full",
        @"power.relative_state_of_charge",
        @"power.percent",
        @"power.percentage",
    ];
    for (NSString *key in keys) {
        NSError *error = nil;
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        NSString *raw = [self _getVar:key connection:connection error:&error];
        NSLog(@"[BatterySgd] %@ raw='%@' error='%@' ms=%.0f",
              key,
              raw,
              error.localizedDescription ?: @"nil",
              (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);
        NSNumber *parsed = [self _parsePercentString:raw];
        if (parsed != nil) {
            return parsed;
        }
    }
    return nil;
}

+ (NSNumber *)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection {
    return [self batteryPercentFromConnection:connection linkFailed:NULL];
}

+ (NSNumber *)batteryPercentFromConnection:(id<ZebraPrinterConnection, NSObject>)connection
                                 linkFailed:(BOOL *)linkFailed {
    if (linkFailed != NULL) {
        *linkFailed = NO;
    }
    @try {
        NSLog(@"[BatterySgd] begin connected=%@",
              [connection isConnected] ? @"YES" : @"NO");
        [self _drainConnectionOnce:connection];

        NSError *sourceError = nil;
        CFAbsoluteTime t0 = CFAbsoluteTimeGetCurrent();
        NSString *sourceRaw = [self _getVar:@"power.source" connection:connection error:&sourceError];
        NSString *source = [[sourceRaw uppercaseString]
            stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSLog(@"[BatterySgd] power.source raw='%@' normalized='%@' error='%@' ms=%.0f",
              sourceRaw,
              source,
              sourceError.localizedDescription ?: @"nil",
              (CFAbsoluteTimeGetCurrent() - t0) * 1000.0);

        // A transport error with no scalar means the radio is gone. An unparseable
        // scalar without an error is AC power or an unknown key, not a disconnect.
        if (sourceError != nil && ![self _looksLikeValidSgdScalar:sourceRaw]) {
            NSLog(@"[BatterySgd] link failed power.source error=%@", sourceError);
            if (linkFailed != NULL) {
                *linkFailed = YES;
            }
            return nil;
        }

        // Missing / garbage source must not block charge reads — only skip on clear AC/line/mains.
        if ([self _looksLikeValidSgdScalar:sourceRaw] && [self _isAcPowerSource:source]) {
            NSLog(@"[BatterySgd] skipping percent — AC/line/mains source '%@'", source);
            return nil;
        }

        NSNumber *parsed = [self _readChargePercent:connection];
        NSLog(@"[BatterySgd] parsed batteryPercent=%@", parsed);
        return parsed;
    } @catch (NSException *exception) {
        NSLog(@"[BatterySgd] exception: %@", exception);
        if (linkFailed != NULL) {
            *linkFailed = YES;
        }
        return nil;
    }
}

@end
