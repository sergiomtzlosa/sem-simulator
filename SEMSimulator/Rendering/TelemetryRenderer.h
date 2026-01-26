#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@class SEMPhysicsEngine;
@class SEMSpecimen;

NS_ASSUME_NONNULL_BEGIN

@interface TelemetryRenderer : NSObject
- (void)updateTexture:(id<MTLTexture>)texture
               engine:(SEMPhysicsEngine *)engine
             specimen:(nullable SEMSpecimen *)specimen;
@end

NS_ASSUME_NONNULL_END
