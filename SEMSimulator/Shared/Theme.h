#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface Theme : NSObject

+ (NSColor *)consoleBackground;
+ (NSColor *)panelFace;
+ (NSColor *)panelEdge;
+ (NSColor *)panelHighlight;
+ (NSColor *)labelColor;
+ (NSColor *)dimLabelColor;
+ (NSColor *)accentGreen;
+ (NSColor *)accentAmber;
+ (NSColor *)accentRed;
+ (NSColor *)crtGreen;
+ (NSColor *)crtAmber;
+ (NSColor *)crtWhite;

+ (NSFont *)labelFont;
+ (NSFont *)smallFont;
+ (NSFont *)titleFont;
+ (NSFont *)valueFont;
+ (NSFont *)monoFontOfSize:(CGFloat)size;
+ (NSFont *)condensedFontOfSize:(CGFloat)size weight:(NSFontWeight)weight;

+ (NSColor *)colorWithHex:(uint32_t)hex;
+ (void)styleLabel:(NSTextField *)label;
+ (void)styleValueLabel:(NSTextField *)label;
+ (void)stylePopupButton:(NSPopUpButton *)popup;
+ (NSButton *)consoleButtonWithTitle:(NSString *)title target:(nullable id)target action:(nullable SEL)action;

@end

NS_ASSUME_NONNULL_END
