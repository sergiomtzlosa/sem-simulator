#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface RockerSwitchControl : NSControl

@property (nonatomic, assign, getter=isOn) BOOL on;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSColor *ledColor;

- (instancetype)initWithTitle:(NSString *)title;

@end

NS_ASSUME_NONNULL_END
