#import "RotaryKnobControl.h"
#import "Theme.h"

static double KnobClamp(double v, double lo, double hi) { return MIN(MAX(v, lo), hi); }

@implementation RotaryKnobControl {
    double _minValue;
    double _maxValue;
    double _doubleValue;
    double _defaultValue;
    double _step;
    double _fineStep;
    NSString *_label;
    NSString *_unit;
    NSInteger _majorTickCount;
    BOOL _logarithmic;
    SEMKnobValueFormatter _valueFormatter;
}

- (instancetype)initWithLabel:(NSString *)label
                          min:(double)min
                          max:(double)max
                 defaultValue:(double)def
                         unit:(NSString *)unit {
    self = [super initWithFrame:NSMakeRect(0, 0, 84, 104)];
    if (self) {
        _label = [label copy];
        _unit = [unit copy];
        _minValue = min;
        _maxValue = max;
        _defaultValue = KnobClamp(def, min, max);
        _doubleValue = _defaultValue;
        _step = (max - min) / 100.0;
        _fineStep = _step / 10.0;
        _majorTickCount = 10;
        _logarithmic = NO;
        self.focusRingType = NSFocusRingTypeNone;
    }
    return self;
}

- (NSSize)intrinsicContentSize { return NSMakeSize(84, 104); }

- (void)setMinValue:(double)minValue { _minValue = minValue; [self setNeedsDisplay:YES]; }
- (void)setMaxValue:(double)maxValue { _maxValue = maxValue; [self setNeedsDisplay:YES]; }
- (double)minValue { return _minValue; }
- (double)maxValue { return _maxValue; }
- (double)doubleValue { return _doubleValue; }
- (double)defaultValue { return _defaultValue; }
- (void)setDefaultValue:(double)defaultValue { _defaultValue = KnobClamp(defaultValue, _minValue, _maxValue); }
- (double)step { return _step; }
- (void)setStep:(double)step { _step = MAX(step, 1e-9); }
- (double)fineStep { return _fineStep; }
- (void)setFineStep:(double)fineStep { _fineStep = MAX(fineStep, 1e-9); }
- (NSString *)label { return _label; }
- (void)setLabel:(NSString *)label { _label = [label copy]; [self setNeedsDisplay:YES]; }
- (NSString *)unit { return _unit; }
- (void)setUnit:(NSString *)unit { _unit = [unit copy]; [self setNeedsDisplay:YES]; }
- (NSInteger)majorTickCount { return _majorTickCount; }
- (void)setMajorTickCount:(NSInteger)majorTickCount { _majorTickCount = MAX(majorTickCount, 2); [self setNeedsDisplay:YES]; }
- (BOOL)isLogarithmic { return _logarithmic; }
- (void)setLogarithmic:(BOOL)logarithmic { _logarithmic = logarithmic; [self setNeedsDisplay:YES]; }
- (SEMKnobValueFormatter)valueFormatter { return _valueFormatter; }
- (void)setValueFormatter:(SEMKnobValueFormatter)valueFormatter { _valueFormatter = [valueFormatter copy]; [self setNeedsDisplay:YES]; }

- (void)setDoubleValue:(double)value {
    double lo = _logarithmic ? MAX(_minValue, 1e-9) : _minValue;
    _doubleValue = KnobClamp(value, lo, _maxValue);
    [self setNeedsDisplay:YES];
}

- (void)setDoubleValueSilently:(double)value {
    [self setDoubleValue:value];
}

- (double)normalizedValue {
    if (_logarithmic) {
        double lo = log10(MAX(_minValue, 1e-9));
        double hi = log10(MAX(_maxValue, 1e-9));
        if (hi <= lo) return 0.0;
        return (log10(MAX(_doubleValue, 1e-9)) - lo) / (hi - lo);
    }
    if (_maxValue <= _minValue) return 0.0;
    return (_doubleValue - _minValue) / (_maxValue - _minValue);
}

- (double)valueForNormalized:(double)normalized {
    normalized = KnobClamp(normalized, 0.0, 1.0);
    if (_logarithmic) {
        double lo = log10(MAX(_minValue, 1e-9));
        double hi = log10(MAX(_maxValue, 1e-9));
        return pow(10.0, lo + normalized * (hi - lo));
    }
    return _minValue + normalized * (_maxValue - _minValue);
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    CGFloat alpha = self.isEnabled ? 1.0 : 0.42;
    [NSGraphicsContext saveGraphicsState];
    [[NSColor colorWithWhite:0 alpha:alpha] set];
    NSRectFillUsingOperation(NSZeroRect, NSCompositingOperationClear);

    NSRect bounds = self.bounds;
    NSDictionary *labelAttrs = @{NSFontAttributeName: [Theme smallFont],
                                 NSForegroundColorAttributeName: [[Theme colorWithHex:0x39352D] colorWithAlphaComponent:alpha]};
    NSSize labelSize = [_label sizeWithAttributes:labelAttrs];
    [_label drawAtPoint:NSMakePoint(NSMidX(bounds) - labelSize.width / 2.0, NSMaxY(bounds) - 13)
         withAttributes:labelAttrs];

    NSPoint center = NSMakePoint(NSMidX(bounds), NSMinY(bounds) + 47);
    CGFloat tickRadius = 33;
    CGFloat startAngle = 225.0;
    CGFloat sweep = -270.0;

    for (int i = 0; i <= _majorTickCount * 2; i++) {
        double frac = (double)i / (double)(_majorTickCount * 2);
        CGFloat angle = (startAngle + sweep * frac) * M_PI / 180.0;
        BOOL major = (i % 2 == 0);
        CGFloat inner = tickRadius - (major ? 6 : 3);
        CGFloat outer = tickRadius;
        NSPoint p1 = NSMakePoint(center.x + cos(angle) * inner, center.y + sin(angle) * inner);
        NSPoint p2 = NSMakePoint(center.x + cos(angle) * outer, center.y + sin(angle) * outer);
        NSBezierPath *tick = [NSBezierPath bezierPath];
        [tick moveToPoint:p1];
        [tick lineToPoint:p2];
        [[[Theme colorWithHex:0x514C42] colorWithAlphaComponent:alpha * (major ? 0.9 : 0.55)] setStroke];
        tick.lineWidth = major ? 1.1 : 0.6;
        [tick stroke];
    }

    CGFloat knobRadius = 26;
    NSRect knobRect = NSMakeRect(center.x - knobRadius, center.y - knobRadius, knobRadius * 2, knobRadius * 2);
    NSBezierPath *shadowPath = [NSBezierPath bezierPathWithOvalInRect:NSOffsetRect(knobRect, 0, -2)];
    [[[NSColor blackColor] colorWithAlphaComponent:0.25 * alpha] setFill];
    [shadowPath fill];

    NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:knobRect];
    NSGradient *knobGradient = [[NSGradient alloc] initWithStartingColor:[[Theme colorWithHex:0xE4DED0] colorWithAlphaComponent:alpha]
                                                             endingColor:[[Theme colorWithHex:0x6A6458] colorWithAlphaComponent:alpha]];
    [knobGradient drawInBezierPath:knob angle:-60];

    [[[Theme colorWithHex:0x312E28] colorWithAlphaComponent:alpha] setStroke];
    knob.lineWidth = 1.3;
    [knob stroke];

    NSBezierPath *inner = [NSBezierPath bezierPathWithOvalInRect:NSInsetRect(knobRect, 5, 5)];
    [[[NSColor whiteColor] colorWithAlphaComponent:0.18 * alpha] setStroke];
    inner.lineWidth = 1.0;
    [inner stroke];

    double norm = KnobClamp([self normalizedValue], 0.0, 1.0);
    CGFloat pointerAngle = (startAngle + sweep * norm) * M_PI / 180.0;
    NSPoint pointerStart = NSMakePoint(center.x + cos(pointerAngle) * 7, center.y + sin(pointerAngle) * 7);
    NSPoint pointerEnd = NSMakePoint(center.x + cos(pointerAngle) * (knobRadius - 4),
                                     center.y + sin(pointerAngle) * (knobRadius - 4));
    NSBezierPath *pointer = [NSBezierPath bezierPath];
    [pointer moveToPoint:pointerStart];
    [pointer lineToPoint:pointerEnd];
    [[[Theme colorWithHex:0x24211C] colorWithAlphaComponent:alpha] setStroke];
    pointer.lineWidth = 2.2;
    pointer.lineCapStyle = NSLineCapStyleRound;
    [pointer stroke];

    NSString *valueText;
    if (_valueFormatter) {
        valueText = _valueFormatter(_doubleValue);
    } else {
        valueText = [NSString stringWithFormat:@"%.2f %@", _doubleValue, _unit ?: @""];
    }
    if (!valueText) valueText = @"";
    NSDictionary *valueAttrs = @{NSFontAttributeName: [Theme monoFontOfSize:9],
                                 NSForegroundColorAttributeName: [[Theme colorWithHex:0x2B2821] colorWithAlphaComponent:alpha]};
    NSSize valueSize = [valueText sizeWithAttributes:valueAttrs];
    [valueText drawAtPoint:NSMakePoint(NSMidX(bounds) - valueSize.width / 2.0, 4) withAttributes:valueAttrs];

    [NSGraphicsContext restoreGraphicsState];
}

- (void)mouseDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    [self.window makeFirstResponder:self];

    if (event.clickCount == 2) {
        self.doubleValue = _defaultValue;
        [self sendAction:self.action to:self.target];
        return;
    }

    NSPoint start = [self convertPoint:event.locationInWindow fromView:nil];
    double startNorm = [self normalizedValue];

    while (YES) {
        NSEvent *next = [self.window nextEventMatchingMask:(NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp)
                                                untilDate:[NSDate distantFuture]
                                                   inMode:NSEventTrackingRunLoopMode
                                                  dequeue:YES];
        if (!next || next.type == NSEventTypeLeftMouseUp) break;
        NSPoint p = [self convertPoint:next.locationInWindow fromView:nil];
        double delta = ((p.y - start.y) / 150.0) + ((p.x - start.x) / 500.0);
        if (next.modifierFlags & NSEventModifierFlagShift) delta *= 0.12;
        double newNorm = KnobClamp(startNorm + delta, 0.0, 1.0);
        self.doubleValue = [self valueForNormalized:newNorm];
        [self sendAction:self.action to:self.target];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    if (!self.isEnabled) return;
    double delta = event.scrollingDeltaY / 120.0;
    if (event.modifierFlags & NSEventModifierFlagShift) delta *= 0.15;
    if (fabs(delta) < 0.0001) return;
    double newNorm = KnobClamp([self normalizedValue] + delta * 0.03, 0.0, 1.0);
    self.doubleValue = [self valueForNormalized:newNorm];
    [self sendAction:self.action to:self.target];
}

- (BOOL)acceptsFirstResponder { return YES; }

- (void)keyDown:(NSEvent *)event {
    if (!self.isEnabled) return;
    double direction = 0;
    if (event.keyCode == 123 || event.keyCode == 125) direction = -1;
    else if (event.keyCode == 124 || event.keyCode == 126) direction = 1;
    else { [super keyDown:event]; return; }

    if (_logarithmic) {
        double newNorm = KnobClamp([self normalizedValue] + direction * 0.01, 0.0, 1.0);
        self.doubleValue = [self valueForNormalized:newNorm];
    } else {
        double amount = (event.modifierFlags & NSEventModifierFlagShift) ? _fineStep : _step;
        self.doubleValue = _doubleValue + direction * amount;
    }
    [self sendAction:self.action to:self.target];
}

- (id)accessibilityRole { return NSAccessibilitySliderRole; }
- (NSString *)accessibilityLabel { return self.label; }
- (NSNumber *)accessibilityValue { return @(self.doubleValue); }
- (NSNumber *)accessibilityMinValue { return @(self.minValue); }
- (NSNumber *)accessibilityMaxValue { return @(self.maxValue); }

@end
