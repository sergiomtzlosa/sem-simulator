#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface LEDIndicatorView : NSView
@property (nonatomic, strong) NSColor *color;
@property (nonatomic, assign, getter=isOn) BOOL on;
@end

NS_ASSUME_NONNULL_END
