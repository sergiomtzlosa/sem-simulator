#import "TelemetryRenderer.h"
#import <CoreText/CoreText.h>
#import <AppKit/AppKit.h>
#import "SEMPhysicsEngine.h"
#import "SEMSpecimen.h"
#import "SEMScaleMath.h"

static const size_t SEMOverlayWidth = 1024;
static const size_t SEMOverlayHeight = 768;

static void SEMDrawLine(CGContextRef ctx, NSString *text, CGFloat x, CGFloat top, CGFloat size, CGFloat alpha, BOOL rightAlign) {
    if (text.length == 0) return;
    CTFontRef font = CTFontCreateWithName(CFSTR("Menlo-Bold"), size, NULL);
    CGColorRef white = CGColorCreateGenericRGB(1.0, 1.0, 1.0, alpha);
    NSDictionary *attrs = @{(__bridge id)kCTFontAttributeName: (__bridge id)font,
                            (__bridge id)kCTForegroundColorAttributeName: (__bridge id)white};
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:attrs];
    CTLineRef line = CTLineCreateWithAttributedString((__bridge CFAttributedStringRef)string);
    double width = CTLineGetTypographicBounds(line, NULL, NULL, NULL);
    CGFloat drawX = rightAlign ? x - (CGFloat)width : x;
    CGFloat ascent = CTFontGetAscent(font);
    CGContextSetTextPosition(ctx, drawX, (CGFloat)SEMOverlayHeight - top - ascent);
    CTLineDraw(line, ctx);
    CFRelease(line);
    CFRelease(font);
    CGColorRelease(white);
}

@implementation TelemetryRenderer {
    CGContextRef _context;
    uint8_t *_pixels;
}

- (void)dealloc {
    if (_context) CGContextRelease(_context);
    free(_pixels);
}

- (void)ensureContext {
    if (_context) return;
    _pixels = calloc(SEMOverlayWidth * SEMOverlayHeight * 4, sizeof(uint8_t));
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    _context = CGBitmapContextCreate(_pixels, SEMOverlayWidth, SEMOverlayHeight, 8,
                                     SEMOverlayWidth * 4, space,
                                     kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    CGContextSetShouldAntialias(_context, YES);
}

- (void)updateTexture:(id<MTLTexture>)texture
               engine:(SEMPhysicsEngine *)engine
             specimen:(SEMSpecimen *)specimen {
    [self ensureContext];
    if (!_context || !texture) return;

    CGContextClearRect(_context, CGRectMake(0, 0, SEMOverlayWidth, SEMOverlayHeight));

    NSString *specimenName = specimen.name.length > 0 ? specimen.name.uppercaseString : @"NO SPECIMEN";
    SEMDrawLine(_context, @"SEM SIMULATOR", 34, 26, 30, 0.92, NO);
    SEMDrawLine(_context, specimenName, 34, 62, 18, 0.78, NO);

    SEMDrawLine(_context, [NSString stringWithFormat:@"%ld kV", (long)engine.acceleratingVoltageKV], 990, 26, 21, 0.9, YES);
    SEMDrawLine(_context, [NSString stringWithFormat:@"MAG %@", [SEMScaleMath formatMagnification:engine.magnification]], 990, 54, 21, 0.9, YES);
    SEMDrawLine(_context, [NSString stringWithFormat:@"WD %.1f mm", engine.workingDistanceMM], 990, 82, 18, 0.82, YES);

    NSString *detector = engine.detectorMode == SEMDetectorModeBSE ? @"BSE" : @"SE";
    NSString *scan = engine.scanMode == SEMScanModeTV ? @"TV" : (engine.scanMode == SEMScanModeSlow ? @"SLOW" : @"PHOTO");
    SEMDrawLine(_context, [NSString stringWithFormat:@"%@   %@   %@", detector, scan, SEMVacuumStateName(engine.vacuumState)], 34, 664, 17, 0.78, NO);
    SEMDrawLine(_context, engine.statusMessage ?: @"", 34, 692, 15, 0.62, NO);
    SEMDrawLine(_context, engine.beamOn ? @"BEAM ON" : @"BEAM BLANKED", 34, 718, 15, engine.beamOn ? 0.65 : 0.9, NO);

    double fov = [SEMScaleMath fieldOfViewMicrometersForMagnification:engine.magnification];
    double barUm = [SEMScaleMath niceScaleBarMicrometersForFieldOfView:fov];
    CGFloat barPixels = (CGFloat)(barUm / fov * (double)SEMOverlayWidth);
    barPixels = MAX(36.0, MIN(barPixels, 420.0));
    CGFloat barX = (CGFloat)SEMOverlayWidth - 40.0 - barPixels;
    CGFloat barY = 56.0;
    CGContextSetLineWidth(_context, 3.0);
    CGContextSetRGBStrokeColor(_context, 1.0, 1.0, 1.0, 0.88);
    CGContextMoveToPoint(_context, barX, barY);
    CGContextAddLineToPoint(_context, barX + barPixels, barY);
    CGContextMoveToPoint(_context, barX, barY - 6.0);
    CGContextAddLineToPoint(_context, barX, barY + 6.0);
    CGContextMoveToPoint(_context, barX + barPixels, barY - 6.0);
    CGContextAddLineToPoint(_context, barX + barPixels, barY + 6.0);
    CGContextStrokePath(_context);

    NSString *scaleText = [SEMScaleMath formatMicrometers:barUm];
    SEMDrawLine(_context, scaleText, (CGFloat)SEMOverlayWidth - 40.0, 672, 16, 0.8, YES);
    SEMDrawLine(_context, @"SCALE", (CGFloat)SEMOverlayWidth - 40.0, 694, 11, 0.45, YES);

    MTLRegion region = MTLRegionMake2D(0, 0, SEMOverlayWidth, SEMOverlayHeight);
    [texture replaceRegion:region mipmapLevel:0 withBytes:_pixels bytesPerRow:SEMOverlayWidth * 4];
}

@end
