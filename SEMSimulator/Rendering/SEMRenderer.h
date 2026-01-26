#import <Foundation/Foundation.h>
#import <MetalKit/MetalKit.h>
#import "SEMTypes.h"

@class SEMPhysicsEngine;
@class SEMSpecimen;

NS_ASSUME_NONNULL_BEGIN

@interface SEMRenderer : NSObject

- (instancetype)initWithDevice:(id<MTLDevice>)device;
@property (nonatomic, readonly, nullable) NSString *shaderError;

- (void)drawInView:(MTKView *)view
             engine:(SEMPhysicsEngine *)engine
           specimen:(nullable SEMSpecimen *)specimen
       phosphorMode:(SEMPhosphorMode)phosphorMode
        interactive:(BOOL)interactive;

- (nullable NSImage *)currentFrameImage;

@end

NS_ASSUME_NONNULL_END
