#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface PressureGaugeView : NSView
@property (nonatomic, assign) double pressurePa;
@property (nonatomic, assign, getter=isTorr) BOOL torr;
@end

NS_ASSUME_NONNULL_END
