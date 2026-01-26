#import "PanelView.h"
#import "Theme.h"

@implementation PanelView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = NO;
        _title = @"";
    }
    return self;
}

- (BOOL)isFlipped { return NO; }

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect r = NSInsetRect(self.bounds, 1.0, 1.0);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:r xRadius:6 yRadius:6];

    NSGradient *gradient = [[NSGradient alloc] initWithStartingColor:[Theme panelFace]
                                                         endingColor:[Theme colorWithHex:0x9E9788]];
    [gradient drawInBezierPath:path angle:-90.0];

    [[Theme panelEdge] setStroke];
    path.lineWidth = 1.5;
    [path stroke];

    NSBezierPath *highlight = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(r, 2, 2) xRadius:5 yRadius:5];
    [[[Theme panelHighlight] colorWithAlphaComponent:0.45] setStroke];
    highlight.lineWidth = 0.8;
    [highlight stroke];

    for (NSValue *value in @[[NSValue valueWithPoint:NSMakePoint(10, 10)],
                             [NSValue valueWithPoint:NSMakePoint(NSMaxX(r) - 10, 10)],
                             [NSValue valueWithPoint:NSMakePoint(10, NSMaxY(r) - 10)],
                             [NSValue valueWithPoint:NSMakePoint(NSMaxX(r) - 10, NSMaxY(r) - 10)]]) {
        NSPoint p = value.pointValue;
        NSBezierPath *screw = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(p.x - 2.5, p.y - 2.5, 5, 5)];
        [[Theme colorWithHex:0x777063] setFill];
        [screw fill];
        [[Theme colorWithHex:0x4B463D] setStroke];
        screw.lineWidth = 0.7;
        [screw stroke];
        NSBezierPath *slot = [NSBezierPath bezierPath];
        [slot moveToPoint:NSMakePoint(p.x - 1.5, p.y)];
        [slot lineToPoint:NSMakePoint(p.x + 1.5, p.y)];
        [[Theme colorWithHex:0x3D3932] setStroke];
        slot.lineWidth = 0.8;
        [slot stroke];
    }

    if (self.title.length > 0) {
        NSDictionary *attrs = @{NSFontAttributeName: [Theme titleFont],
                                NSForegroundColorAttributeName: [Theme colorWithHex:0x3D3932]};
        NSSize size = [self.title sizeWithAttributes:attrs];
        [self.title drawAtPoint:NSMakePoint(16, NSMaxY(r) - 19) withAttributes:attrs];
        NSBezierPath *line = [NSBezierPath bezierPath];
        [line moveToPoint:NSMakePoint(16, NSMaxY(r) - 24)];
        [line lineToPoint:NSMakePoint(NSMaxX(r) - 16, NSMaxY(r) - 24)];
        [[[Theme panelEdge] colorWithAlphaComponent:0.55] setStroke];
        line.lineWidth = 0.7;
        [line stroke];
        (void)size;
    }
}

@end
