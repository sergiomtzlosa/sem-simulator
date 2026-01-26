#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSString * _Nullable (^SEMKnobValueFormatter)(double value);

@interface RotaryKnobControl : NSControl

@property (nonatomic, assign) double minValue;
@property (nonatomic, assign) double maxValue;
@property (atomic, assign) double doubleValue;
@property (nonatomic, readonly) double normalizedValue;
@property (nonatomic, assign) double defaultValue;
@property (nonatomic, assign) double step;
@property (nonatomic, assign) double fineStep;
@property (nonatomic, copy) NSString *label;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, assign) NSInteger majorTickCount;
@property (nonatomic, assign, getter=isLogarithmic) BOOL logarithmic;
@property (nonatomic, copy, nullable) SEMKnobValueFormatter valueFormatter;

- (instancetype)initWithLabel:(NSString *)label
                          min:(double)min
                          max:(double)max
                 defaultValue:(double)def
                         unit:(NSString *)unit;
- (void)setDoubleValueSilently:(double)value;

@end

NS_ASSUME_NONNULL_END
