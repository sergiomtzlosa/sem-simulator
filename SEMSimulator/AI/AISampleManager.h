#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

@class AISampleRecipe;
@class SEMSpecimen;
@class SpecimenPreset;

NS_ASSUME_NONNULL_BEGIN

@interface AISampleManager : NSObject
- (instancetype)initWithDevice:(id<MTLDevice>)device;

/// Synthesizes a specimen locally from the semantic prompt parser. Used by the
/// default startup specimen and the control API.
- (void)generateSpecimenForPrompt:(NSString *)prompt
                        variation:(NSUInteger)variation
                       completion:(void (^)(SEMSpecimen * _Nullable specimen, NSError * _Nullable error))completion;

/// Synthesizes a specimen from an explicit recipe on the generation queue.
- (void)generateSpecimenWithRecipe:(AISampleRecipe *)recipe
                        completion:(void (^)(SEMSpecimen * _Nullable specimen, NSError * _Nullable error))completion;

/// Loads a bundled built-in model entirely offline. The model's explicit recipe
/// is used when present; otherwise the semantic prompt parser supplies one.
- (void)generateSpecimenForPreset:(SpecimenPreset *)preset
                       completion:(void (^)(SEMSpecimen * _Nullable specimen, NSError * _Nullable error))completion;

/// Asks the OpenCode server for a strict JSON specimen recipe, then synthesizes
/// height, normal, and Z maps locally. The completion runs on the main queue.
/// If OpenCode is unreachable, rate-limited, or returns an invalid recipe, the
/// manager falls back to the local semantic parser so generation still succeeds.
- (void)generateSpecimenUsingOpenCodeForPrompt:(NSString *)prompt
                                     variation:(NSUInteger)variation
                                    completion:(void (^)(SEMSpecimen * _Nullable specimen, NSError * _Nullable error))completion;

/// Short explanation of the most recent local fallback, or nil when OpenCode
/// supplied the recipe. Read this immediately after the completion runs.
@property (nonatomic, copy, readonly, nullable) NSString *lastGenerationNote;
@end

NS_ASSUME_NONNULL_END
