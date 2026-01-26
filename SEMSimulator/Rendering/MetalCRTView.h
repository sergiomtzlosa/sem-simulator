#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import "SEMTypes.h"

@class SEMPhysicsEngine;
@class SEMSpecimen;

NS_ASSUME_NONNULL_BEGIN

@interface MetalCRTView : MTKView

@property (nonatomic, strong, nullable) SEMPhysicsEngine *engine;
@property (nonatomic, strong, nullable) SEMSpecimen *specimen;
@property (nonatomic, assign) SEMPhosphorMode phosphorMode;

@property (nonatomic, readonly, nullable) NSString *shaderError;
@property (nonatomic, readonly, nullable) NSImage *currentFrameImage;

- (instancetype)initWithFrame:(NSRect)frameRect
                       device:(nullable id<MTLDevice>)device
                       engine:(SEMPhysicsEngine *)engine;

- (void)drawFrame;
- (void)zoomByFactor:(double)factor;
- (void)resetMagnification;

@end

NS_ASSUME_NONNULL_END
