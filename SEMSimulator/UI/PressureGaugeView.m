#import "PressureGaugeView.h"
#import "Theme.h"
#import "SEMScaleMath.h"

@implementation PressureGaugeView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _pressurePa = 101325.0;
    }
    return self;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(174, 118); }

- (void)setPressurePa:(double)pressurePa {
    _pressurePa = MAX(pressurePa, 1e-6);
    [self setNeedsDisplay:YES];
}

- (void)setTorr:(BOOL)torr {
    _torr = torr;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect bounds = self.bounds;
    NSPoint center = NSMakePoint(NSMidX(bounds), NSMidY(bounds) + 9);
    CGFloat radius = 45;

    NSRect bezelRect = NSMakeRect(center.x - radius - 8, center.y - radius - 8, (radius + 8) * 2, (radius + 8) * 2);
    NSBezierPath *bezel = [NSBezierPath bezierPathWithOvalInRect:bezelRect];
    NSGradient *bezelGradient = [[NSGradient alloc] initWithStartingColor:[Theme colorWithHex:0x3A3731]
                                                               endingColor:[Theme colorWithHex:0x161512]];
    [bezelGradient drawInBezierPath:bezel angle:-90];
    [[Theme colorWithHex:0x696358] setStroke];
    bezel.lineWidth = 1.2;
    [bezel stroke];

    NSRect faceRect = NSInsetRect(bezelRect, 7, 7);
    NSBezierPath *face = [NSBezierPath bezierPathWithOvalInRect:faceRect];
    [[Theme colorWithHex:0xD8D1C0] setFill];
    [face fill];
    [[Theme colorWithHex:0x716B5F] setStroke];
    face.lineWidth = 0.8;
    [face stroke];

    double logMin = -5.0;
    double logMax = 5.0;
    double t = (log10(_pressurePa) - logMin) / (logMax - logMin);
    t = MIN(MAX(t, 0.0), 1.0);

    CGFloat startAngle = 210.0;
    CGFloat sweep = -240.0;

    NSArray<NSNumber *> *zoneEnds = @[@0.50, @0.75, @1.0];
    NSArray<NSColor *> *zoneColors = @[[Theme colorWithHex:0x3D8D54],
                                       [Theme colorWithHex:0xC49A37],
                                       [Theme colorWithHex:0xA63A31]];
    CGFloat zoneStart = 0.0;
    for (NSUInteger i = 0; i < zoneEnds.count; i++) {
        CGFloat zoneEnd = zoneEnds[i].doubleValue;
        NSBezierPath *arc = [NSBezierPath bezierPath];
        [arc appendBezierPathWithArcWithCenter:center
                                        radius:radius - 5
                                    startAngle:startAngle + sweep * zoneStart
                                      endAngle:startAngle + sweep * zoneEnd
                                     clockwise:(sweep < 0)];
        [zoneColors[i] setStroke];
        arc.lineWidth = 2.2;
        [arc stroke];
        zoneStart = zoneEnd;
    }

    NSDictionary *tickAttrs = @{NSFontAttributeName: [Theme monoFontOfSize:6.5],
                                NSForegroundColorAttributeName: [Theme colorWithHex:0x4D483E]};
    for (int i = 0; i <= 10; i++) {
        double frac = i / 10.0;
        CGFloat angle = (startAngle + sweep * frac) * M_PI / 180.0;
        CGFloat inner = radius - (i % 5 == 0 ? 12 : 8);
        CGFloat outer = radius - 2;
        NSPoint p1 = NSMakePoint(center.x + cos(angle) * inner, center.y + sin(angle) * inner);
        NSPoint p2 = NSMakePoint(center.x + cos(angle) * outer, center.y + sin(angle) * outer);
        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:p1];
        [tick lineToPoint:p2];
        [[Theme colorWithHex:0x4D483E] setStroke];
        tick.lineWidth = (i % 5 == 0) ? 1.3 : 0.7;
        [tick stroke];
    }

    NSString *lowLabel = @"1e-5";
    NSString *highLabel = @"1e5";
    [lowLabel drawAtPoint:NSMakePoint(center.x - radius + 2, center.y - 27) withAttributes:tickAttrs];
    [highLabel drawAtPoint:NSMakePoint(center.x + radius - 24, center.y - 27) withAttributes:tickAttrs];

    CGFloat needleAngle = (startAngle + sweep * t) * M_PI / 180.0;
    NSPoint needleEnd = NSMakePoint(center.x + cos(needleAngle) * (radius - 13),
                                    center.y + sin(needleAngle) * (radius - 13));
    NSBezierPath *needle = [NSBezierPath bezierPath];
    [needle moveToPoint:center];
    [needle lineToPoint:needleEnd];
    [[Theme colorWithHex:0x8C2E28] setStroke];
    needle.lineWidth = 2.0;
    [needle stroke];

    NSBezierPath *hub = [NSBezierPath bezierPathWithOvalInRect:NSMakeRect(center.x - 4, center.y - 4, 8, 8)];
    [[Theme colorWithHex:0x24211D] setFill];
    [hub fill];
    [[Theme colorWithHex:0xB5AD9E] setStroke];
    hub.lineWidth = 0.8;
    [hub stroke];

    NSString *pressureText = [SEMScaleMath formatPressurePa:_pressurePa torr:_torr];
    NSDictionary *valueAttrs = @{NSFontAttributeName: [Theme monoFontOfSize:9.5],
                                 NSForegroundColorAttributeName: [Theme colorWithHex:0x24211D]};
    NSSize valueSize = [pressureText sizeWithAttributes:valueAttrs];
    [pressureText drawAtPoint:NSMakePoint(NSMidX(bounds) - valueSize.width / 2.0, 5) withAttributes:valueAttrs];
}

@end
