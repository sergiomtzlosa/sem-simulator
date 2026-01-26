#import <Foundation/Foundation.h>

@class AISampleRecipe;

NS_ASSUME_NONNULL_BEGIN

@interface SemanticPromptParser : NSObject
+ (AISampleRecipe *)recipeForPrompt:(NSString *)prompt variation:(NSUInteger)variation;
@end

NS_ASSUME_NONNULL_END
