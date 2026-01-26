#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>

@class AISampleRecipe;

NS_ASSUME_NONNULL_BEGIN

@interface SpecimenPreset : NSObject

@property (nonatomic, copy, readonly) NSString *identifier;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *category;
@property (nonatomic, copy, readonly) NSString *prompt;
@property (nonatomic, copy, readonly) NSString *detail;
@property (nonatomic, assign, readonly) NSUInteger variation;
@property (nonatomic, copy, readonly, nullable) NSDictionary<NSString *, id> *recipeDictionary;

/// Optional preview image for user-saved specimens. Built-in presets have no
/// preview until they are synthesized.
@property (nonatomic, strong, nullable) NSImage *previewImage;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          category:(NSString *)category
                            prompt:(NSString *)prompt
                            detail:(NSString *)detail
                         variation:(NSUInteger)variation
                  recipeDictionary:(nullable NSDictionary<NSString *, id> *)recipeDictionary;

/// Returns the explicit built-in recipe when available, otherwise falls back to
/// the semantic prompt parser. The recipe name and seed are aligned with the
/// preset so repeated offline loads are deterministic.
- (nullable AISampleRecipe *)recipeRepresentation;

@end

@interface SpecimenLibrary : NSObject

/// The built-in model catalog bundled with the app. These models are always
/// available offline and do not require OpenCode.
+ (NSArray<SpecimenPreset *> *)builtInModels;

/// User-saved specimens from the on-disk store, newest first.
+ (NSArray<SpecimenPreset *> *)savedModels;

/// Built-in models followed by user-saved models. This is the complete offline
/// list shown in the drawer, Settings, and the Specimen menu.
+ (NSArray<SpecimenPreset *> *)offlineModels;

/// Backward-compatible alias for the built-in catalog.
+ (NSArray<SpecimenPreset *> *)offlinePresets;

@end

NS_ASSUME_NONNULL_END
