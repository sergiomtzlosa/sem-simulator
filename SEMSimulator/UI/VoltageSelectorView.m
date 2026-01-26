#import "VoltageSelectorView.h"
#import "Theme.h"
#import "SEMScaleMath.h"

@implementation VoltageSelectorView {
    NSArray<NSNumber *> *_values;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _values = [SEMScaleMath voltageSteps];
        _selectedKV = 15;
    }
    return self;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(300, 38); }

- (void)setSelectedKV:(NSInteger)selectedKV {
    NSInteger nearest = _values.firstObject.integerValue;
    for (NSNumber *n in _values) {
        if (labs((long)(n.integerValue - selectedKV)) < labs((long)(nearest - selectedKV))) {
            nearest = n.integerValue;
        }
    }
    _selectedKV = nearest;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSRect r = NSInsetRect(self.bounds, 1, 1);
    NSBezierPath *track = [NSBezierPath bezierPathWithRoundedRect:r xRadius:5 yRadius:5];
    NSGradient *g = [[NSGradient alloc] initWithStartingColor:[Theme colorWithHex:0x24231F]
                                                   endingColor:[Theme colorWithHex:0x4C483F]];
    [g drawInBezierPath:track angle:-90];
    [[Theme colorWithHex:0x6D675C] setStroke];
    track.lineWidth = 1.0;
    [track stroke];

    CGFloat inset = 5.0;
    CGFloat cellW = (NSWidth(r) - inset * 2) / _values.count;
    NSDictionary *labelAttrs = @{NSFontAttributeName: [Theme monoFontOfSize:8.5],
                                 NSForegroundColorAttributeName: [Theme colorWithHex:0xD9D2C3]};

    for (NSUInteger i = 0; i < _values.count; i++) {
        NSRect cell = NSMakeRect(NSMinX(r) + inset + i * cellW, NSMinY(r) + 5, cellW - 3, NSHeight(r) - 12);
        BOOL selected = (_values[i].integerValue == _selectedKV);
        NSBezierPath *cellPath = [NSBezierPath bezierPathWithRoundedRect:cell xRadius:3 yRadius:3];
        if (selected) {
            NSGradient *sel = [[NSGradient alloc] initWithStartingColor:[Theme colorWithHex:0xE0A438]
                                                               endingColor:[Theme colorWithHex:0x8B5E16]];
            [sel drawInBezierPath:cellPath angle:-90];
            [[Theme colorWithHex:0xFFD37A] setStroke];
            cellPath.lineWidth = 1.0;
            [cellPath stroke];
        } else {
            [[Theme colorWithHex:0x33312C] setFill];
            [cellPath fill];
            [[Theme colorWithHex:0x171613] setStroke];
            cellPath.lineWidth = 0.7;
            [cellPath stroke];
        }
        NSString *label = [NSString stringWithFormat:@"%@", _values[i]];
        NSSize size = [label sizeWithAttributes:labelAttrs];
        NSColor *textColor = selected ? [Theme colorWithHex:0x2A1D07] : [Theme colorWithHex:0xB9B1A2];
        NSDictionary *attrs = @{NSFontAttributeName: [Theme monoFontOfSize:8.5],
                                NSForegroundColorAttributeName: textColor};
        [label drawAtPoint:NSMakePoint(NSMidX(cell) - size.width / 2.0, NSMidY(cell) - size.height / 2.0)
            withAttributes:attrs];
    }

    NSDictionary *kvAttrs = @{NSFontAttributeName: [Theme smallFont],
                              NSForegroundColorAttributeName: [Theme colorWithHex:0x2F2B24]};
    [@"kV" drawAtPoint:NSMakePoint(NSMaxX(r) - 18, NSMaxY(r) - 12) withAttributes:kvAttrs];
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat inset = 5.0;
    CGFloat cellW = (NSWidth(self.bounds) - inset * 2 - 2) / _values.count;
    NSInteger index = (NSInteger)floor((p.x - inset) / cellW);
    index = MAX(0, MIN((NSInteger)_values.count - 1, index));
    self.selectedKV = _values[index].integerValue;
    [self sendAction:self.action to:self.target];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    NSInteger index = [_values indexOfObject:@(_selectedKV)];
    if (event.keyCode == 123) index = MAX(0, index - 1);
    else if (event.keyCode == 124) index = MIN((NSInteger)_values.count - 1, index + 1);
    else { [super keyDown:event]; return; }
    self.selectedKV = _values[index].integerValue;
    [self sendAction:self.action to:self.target];
}

- (id)accessibilityRole { return NSAccessibilityRadioGroupRole; }
- (NSString *)accessibilityLabel { return @"Accelerating voltage"; }
- (NSNumber *)accessibilityValue { return @(self.selectedKV); }

@end
