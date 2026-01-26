#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AISampleRecipe : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *templateName;
@property (nonatomic, assign) double spikes;
@property (nonatomic, assign) double pores;
@property (nonatomic, assign) double roughness;
@property (nonatomic, assign) double cracks;
@property (nonatomic, assign) double fibers;
@property (nonatomic, assign) double grain;
@property (nonatomic, assign) double meanZ;
@property (nonatomic, assign) BOOL conductive;
@property (nonatomic, assign) BOOL coatingRecommended;
@property (nonatomic, assign) NSUInteger seed;
@property (nonatomic, assign) double scaleMicrometers;

+ (nullable instancetype)recipeFromDictionary:(NSDictionary *)dictionary error:(NSError **)error;
+ (nullable instancetype)recipeFromJSONText:(NSString *)text
                               fallbackName:(nullable NSString *)fallbackName
                                      error:(NSError **)error;
- (NSDictionary *)dictionaryRepresentation;

@end

NS_ASSUME_NONNULL_END
