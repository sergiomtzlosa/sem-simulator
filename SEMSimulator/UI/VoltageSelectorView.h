#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface VoltageSelectorView : NSControl
@property (nonatomic, assign) NSInteger selectedKV;
- (instancetype)initWithFrame:(NSRect)frameRect;
@end

NS_ASSUME_NONNULL_END
