#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@class AISampleRecipe;
@class SEMSpecimen;

NS_ASSUME_NONNULL_BEGIN

@interface ProceduralSampleGenerator : NSObject
- (instancetype)initWithDevice:(id<MTLDevice>)device;
- (nullable SEMSpecimen *)generateSpecimenWithRecipe:(AISampleRecipe *)recipe error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
