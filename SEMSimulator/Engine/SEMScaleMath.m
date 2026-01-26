#import "SEMScaleMath.h"

@implementation SEMScaleMath

+ (double)fieldOfViewMicrometersForMagnification:(double)magnification {
    double mag = MAX(magnification, 1.0);
    return 100000.0 / mag;
}

+ (double)niceScaleBarMicrometersForFieldOfView:(double)fieldOfView {
    double target = MAX(fieldOfView * 0.22, 0.000001);
    double exponent = floor(log10(target));
    double base = pow(10.0, exponent);
    double mantissa = target / base;
    double nice = 1.0;
    if (mantissa >= 5.0) nice = 5.0;
    else if (mantissa >= 2.0) nice = 2.0;
    return nice * base;
}

+ (NSString *)formatMagnification:(double)magnification {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.maximumFractionDigits = 0;
    formatter.groupingSeparator = @",";
    formatter.usesGroupingSeparator = YES;
    return [NSString stringWithFormat:@"%@x", [formatter stringFromNumber:@(round(magnification))]];
}

+ (NSString *)formatMicrometers:(double)micrometers {
    if (micrometers >= 1000.0) {
        return [NSString stringWithFormat:@"%.3g mm", micrometers / 1000.0];
    }
    if (micrometers >= 1.0) {
        return [NSString stringWithFormat:@"%.3g µm", micrometers];
    }
    return [NSString stringWithFormat:@"%.2f nm", micrometers * 1000.0];
}

+ (NSString *)formatPressurePa:(double)pa torr:(BOOL)torr {
    double value = torr ? pa * 0.00750062 : pa;
    NSString *unit = torr ? @"Torr" : @"Pa";
    if (value >= 100.0) return [NSString stringWithFormat:@"%.0f %@", value, unit];
    if (value >= 1.0) return [NSString stringWithFormat:@"%.2f %@", value, unit];
    if (value >= 0.001) return [NSString stringWithFormat:@"%.4f %@", value, unit];
    return [NSString stringWithFormat:@"%.2e %@", value, unit];
}

+ (NSArray<NSNumber *> *)voltageSteps {
    return @[@1, @5, @10, @15, @20, @25];
}

@end
