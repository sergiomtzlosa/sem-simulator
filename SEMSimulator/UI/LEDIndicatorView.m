#import "LEDIndicatorView.h"
#import "Theme.h"

@implementation LEDIndicatorView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _color = [Theme accentGreen];
        _on = NO;
    }
    return self;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(14, 14); }

- (void)setOn:(BOOL)on {
    _on = on;
    [self setNeedsDisplay:YES];
}

- (void)setColor:(NSColor *)color {
    _color = color;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect r = NSInsetRect(self.bounds, 2, 2);
    NSBezierPath *ring = [NSBezierPath bezierPathWithOvalInRect:r];
    [[Theme colorWithHex:0x1C1B18] setFill];
    [ring fill];
    [[Theme colorWithHex:0x6D675C] setStroke];
    ring.lineWidth = 1.0;
    [ring stroke];

    NSRect bulbRect = NSInsetRect(r, 2.5, 2.5);
    NSBezierPath *bulb = [NSBezierPath bezierPathWithOvalInRect:bulbRect];
    if (self.isOn) {
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [self.color colorWithAlphaComponent:0.8];
        shadow.shadowBlurRadius = 7.0;
        shadow.shadowOffset = NSZeroSize;
        [shadow set];
        [self.color setFill];
        [bulb fill];
        [[NSColor whiteColor] setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(bulbRect, 2.0, 2.0)] fill];
    } else {
        [[Theme colorWithHex:0x393730] setFill];
        [bulb fill];
    }
}

@end
