#import "RockerSwitchControl.h"
#import "Theme.h"

@implementation RockerSwitchControl

- (instancetype)initWithTitle:(NSString *)title {
    self = [super initWithFrame:NSMakeRect(0, 0, 66, 54)];
    if (self) {
        _title = [title copy];
        _ledColor = [Theme accentGreen];
        _on = NO;
    }
    return self;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(66, 54); }

- (void)setOn:(BOOL)on {
    _on = on;
    [self setNeedsDisplay:YES];
}

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSDictionary *labelAttrs = @{NSFontAttributeName: [Theme smallFont],
                                 NSForegroundColorAttributeName: [Theme colorWithHex:0x3C382F]};
    NSSize labelSize = [self.title sizeWithAttributes:labelAttrs];
    [self.title drawAtPoint:NSMakePoint((NSWidth(self.bounds) - labelSize.width) / 2.0, NSHeight(self.bounds) - 13)
            withAttributes:labelAttrs];

    CGFloat bodyW = 34;
    CGFloat bodyH = 27;
    NSRect bodyRect = NSMakeRect((NSWidth(self.bounds) - bodyW) / 2.0, 16, bodyW, bodyH);
    NSBezierPath *body = [NSBezierPath bezierPathWithRoundedRect:bodyRect xRadius:5 yRadius:5];

    NSColor *topColor = self.isOn ? [Theme colorWithHex:0x8A8376] : [Theme colorWithHex:0x4A463D];
    NSColor *bottomColor = self.isOn ? [Theme colorWithHex:0x3C3932] : [Theme colorWithHex:0x9D9687];
    NSGradient *g = [[NSGradient alloc] initWithStartingColor:topColor endingColor:bottomColor];
    [g drawInBezierPath:body angle:-90];
    [[Theme colorWithHex:0x2A2823] setStroke];
    body.lineWidth = 1.2;
    [body stroke];

    NSRect lever = NSInsetRect(bodyRect, 3, 3);
    if (self.isOn) lever.origin.y += 1.5; else lever.origin.y -= 1.5;
    NSBezierPath *leverPath = [NSBezierPath bezierPathWithRoundedRect:lever xRadius:4 yRadius:4];
    [[[NSColor whiteColor] colorWithAlphaComponent:0.10] setFill];
    [leverPath fill];

    NSDictionary *ioAttrs = @{NSFontAttributeName: [Theme monoFontOfSize:7],
                              NSForegroundColorAttributeName: [[NSColor whiteColor] colorWithAlphaComponent:0.55]};
    [@"I" drawAtPoint:NSMakePoint(NSMidX(bodyRect) - 2.0, NSMaxY(bodyRect) - 9) withAttributes:ioAttrs];
    [@"O" drawAtPoint:NSMakePoint(NSMidX(bodyRect) - 3.0, NSMinY(bodyRect) + 2) withAttributes:ioAttrs];

    NSRect ledRect = NSMakeRect(NSMidX(self.bounds) - 4, 4, 8, 8);
    NSBezierPath *led = [NSBezierPath bezierPathWithOvalInRect:ledRect];
    [[Theme colorWithHex:0x1B1A17] setFill];
    [led fill];
    [[Theme colorWithHex:0x625D52] setStroke];
    led.lineWidth = 0.8;
    [led stroke];
    if (self.isOn) {
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [self.ledColor colorWithAlphaComponent:0.9];
        shadow.shadowBlurRadius = 6;
        [shadow set];
        [self.ledColor setFill];
        [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(ledRect, 1.5, 1.5)] fill];
    }

    if (!self.isEnabled) {
        [[[Theme panelFace] colorWithAlphaComponent:0.45] setFill];
        [body fill];
    }
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    self.on = !self.isOn;
    [self sendAction:self.action to:self.target];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 49 || event.keyCode == 36) {
        self.on = !self.isOn;
        [self sendAction:self.action to:self.target];
    } else {
        [super keyDown:event];
    }
}

- (id)accessibilityRole { return NSAccessibilityCheckBoxRole; }
- (NSString *)accessibilityLabel { return self.title; }
- (NSNumber *)accessibilityValue { return @(self.isOn ? 1 : 0); }

@end
