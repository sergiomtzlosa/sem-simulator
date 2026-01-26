#import "MetalCRTView.h"
#import <Metal/Metal.h>
#import "SEMRenderer.h"
#import "SEMPhysicsEngine.h"

@implementation MetalCRTView {
    SEMRenderer *_renderer;
    double _zoomTarget;
    double _lastZoomMagnification;
    BOOL _zoomTargetActive;
}

- (instancetype)initWithFrame:(NSRect)frameRect
                       device:(id<MTLDevice>)device
                       engine:(SEMPhysicsEngine *)engine {
    self = [super initWithFrame:frameRect device:device];
    if (self) {
        _engine = engine;
        _phosphorMode = SEMPhosphorModeGreen;
        self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
        self.clearColor = MTLClearColorMake(0.01, 0.01, 0.008, 1.0);
        self.framebufferOnly = NO;
        self.paused = YES;
        self.enableSetNeedsDisplay = NO;
        self.preferredFramesPerSecond = 60;
        self.autoResizeDrawable = YES;
        self.layer.masksToBounds = YES;
        _renderer = [[SEMRenderer alloc] initWithDevice:device ?: self.device];
    }
    return self;
}

- (BOOL)isOpaque { return YES; }

- (BOOL)acceptsFirstResponder { return YES; }

- (void)mouseDown:(NSEvent *)event {
    [self.window makeFirstResponder:self];
    [super mouseDown:event];
}

- (void)magnifyWithEvent:(NSEvent *)event {
    if (!self.engine) return;
    double factor = 1.0 + event.magnification;
    if (factor < 0.05) return;
    [self zoomByFactor:factor];
}

- (void)scrollWheel:(NSEvent *)event {
    NSEventModifierFlags flags = event.modifierFlags;
    if (self.engine && (flags & (NSEventModifierFlagOption | NSEventModifierFlagCommand))) {
        double sensitivity = event.hasPreciseScrollingDeltas ? 0.006 : 0.08;
        double factor = exp(event.scrollingDeltaY * sensitivity);
        factor = MIN(MAX(factor, 0.5), 2.0);
        [self zoomByFactor:factor];
        return;
    }
    [super scrollWheel:event];
}

- (void)smartMagnifyWithEvent:(NSEvent *)event {
    [self resetMagnification];
}

- (void)zoomByFactor:(double)factor {
    if (!self.engine || !isfinite(factor) || factor <= 0.0) return;

    double current = self.engine.magnification;
    if (!_zoomTargetActive ||
        fabs(current - _lastZoomMagnification) > MAX(0.5, current * 0.001)) {
        // Rebase the target when a knob or menu command changed magnification.
        _zoomTarget = current;
    }

    _zoomTarget = MIN(MAX(_zoomTarget * factor, 10.0), 100000.0);
    _lastZoomMagnification = current;
    _zoomTargetActive = YES;

    // Do not render from the input event. The 60 Hz simulation timer advances
    // the eased target and renders one frame, so fast wheel/pinch streams are
    // coalesced instead of queueing a drawable for every event.
}

- (void)advanceZoom {
    if (!_zoomTargetActive || !self.engine) return;

    double current = self.engine.magnification;
    double tolerance = MAX(0.5, current * 0.0005);
    if (fabs(current - _lastZoomMagnification) > tolerance) {
        // The engine was changed elsewhere (console knob, preset, control API).
        _zoomTargetActive = NO;
        return;
    }

    double ratio = _zoomTarget / current;
    if (!isfinite(ratio) || ratio <= 0.0) {
        _zoomTargetActive = NO;
        return;
    }

    if (fabs(log(ratio)) < 0.002) {
        [self.engine setMagnification:_zoomTarget];
        _lastZoomMagnification = self.engine.magnification;
        _zoomTargetActive = NO;
        return;
    }

    // Exponential easing in log space gives a consistent feel across the
    // entire 10x–100,000x magnification range.
    double next = current * exp(log(ratio) * 0.34);
    [self.engine setMagnification:next];
    _lastZoomMagnification = self.engine.magnification;
}

- (void)resetMagnification {
    if (!self.engine) return;
    _zoomTargetActive = NO;
    [self.engine setMagnification:1000.0];
    _lastZoomMagnification = self.engine.magnification;
    [self drawFrame];
}

- (void)drawFrame {
    if (!_renderer || !self.engine) return;
    BOOL interactive = _zoomTargetActive;
    [self advanceZoom];
    interactive = interactive || _zoomTargetActive;
    if (self.drawableSize.width < 2 || self.drawableSize.height < 2) return;
    [_renderer drawInView:self
                   engine:self.engine
                 specimen:self.specimen
             phosphorMode:self.phosphorMode
              interactive:interactive];
}

- (NSString *)shaderError {
    return _renderer.shaderError;
}

- (NSImage *)currentFrameImage {
    return [_renderer currentFrameImage];
}

@end
