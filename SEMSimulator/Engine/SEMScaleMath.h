#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SEMScaleMath : NSObject

+ (double)fieldOfViewMicrometersForMagnification:(double)magnification;
+ (double)niceScaleBarMicrometersForFieldOfView:(double)fieldOfView;
+ (NSString *)formatMagnification:(double)magnification;
+ (NSString *)formatMicrometers:(double)micrometers;
+ (NSString *)formatPressurePa:(double)pa torr:(BOOL)torr;
+ (NSArray<NSNumber *> *)voltageSteps;

@end

NS_ASSUME_NONNULL_END
