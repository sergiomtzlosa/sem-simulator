#import "SpecimenLibrary.h"
#import "AISampleRecipe.h"
#import "SavedSpecimenStore.h"
#import "SemanticPromptParser.h"

@implementation SpecimenPreset

- (instancetype)initWithIdentifier:(NSString *)identifier
                              name:(NSString *)name
                          category:(NSString *)category
                            prompt:(NSString *)prompt
                            detail:(NSString *)detail
                         variation:(NSUInteger)variation
                  recipeDictionary:(NSDictionary<NSString *, id> *)recipeDictionary {
    self = [super init];
    if (self) {
        _identifier = [(identifier.length > 0 ? identifier : name) copy];
        _name = [name copy];
        _category = [(category.length > 0 ? category : @"BUILT-IN") copy];
        _prompt = [prompt copy];
        _detail = [detail copy];
        _variation = variation;
        _recipeDictionary = [recipeDictionary copy];
    }
    return self;
}

- (AISampleRecipe *)recipeRepresentation {
    AISampleRecipe *recipe = nil;
    if (self.recipeDictionary.count > 0) {
        recipe = [AISampleRecipe recipeFromDictionary:self.recipeDictionary error:NULL];
    }
    if (!recipe) {
        recipe = [SemanticPromptParser recipeForPrompt:self.prompt variation:self.variation];
    }
    if (!recipe) return nil;

    if (self.name.length > 0) recipe.name = self.name;
    recipe.seed = self.variation;
    return recipe;
}

@end

@implementation SpecimenLibrary

+ (NSArray<SpecimenPreset *> *)modelsFromBundledJSON {
    NSURL *url = nil;
    for (NSBundle *bundle in @[[NSBundle bundleForClass:[self class]], [NSBundle mainBundle]]) {
        url = [bundle URLForResource:@"BuiltInModels" withExtension:@"json"];
        if (url) break;
    }
    if (!url) return @[];

    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return @[];

    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    NSArray *entries = nil;
    if ([object isKindOfClass:[NSDictionary class]]) {
        entries = ((NSDictionary *)object)[@"models"];
    } else if ([object isKindOfClass:[NSArray class]]) {
        entries = object;
    }
    if (![entries isKindOfClass:[NSArray class]]) return @[];

    NSMutableArray<SpecimenPreset *> *models = [NSMutableArray array];
    for (NSDictionary *entry in entries) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;

        NSString *name = [entry[@"name"] isKindOfClass:[NSString class]] ? entry[@"name"] : nil;
        if (name.length == 0) continue;

        NSString *identifier = [entry[@"id"] isKindOfClass:[NSString class]] ? entry[@"id"] : name;
        NSString *category = [entry[@"category"] isKindOfClass:[NSString class]] ? entry[@"category"] : nil;
        NSString *prompt = [entry[@"prompt"] isKindOfClass:[NSString class]] ? entry[@"prompt"] : name;
        NSString *detail = [entry[@"detail"] isKindOfClass:[NSString class]] ? entry[@"detail"] : @"Built-in model";
        NSUInteger variation = [entry[@"variation"] respondsToSelector:@selector(unsignedIntegerValue)]
            ? [entry[@"variation"] unsignedIntegerValue]
            : 1;
        NSDictionary *recipe = [entry[@"recipe"] isKindOfClass:[NSDictionary class]] ? entry[@"recipe"] : nil;

        SpecimenPreset *preset = [[SpecimenPreset alloc] initWithIdentifier:identifier
                                                                      name:name
                                                                  category:category
                                                                    prompt:prompt
                                                                    detail:detail
                                                                 variation:variation
                                                          recipeDictionary:recipe];
        [models addObject:preset];
    }
    return models;
}

+ (NSArray<SpecimenPreset *> *)fallbackPresets {
    return @[
        [[SpecimenPreset alloc] initWithIdentifier:@"pollen-grain"
                                             name:@"Pollen grain"
                                         category:@"BIOLOGICAL"
                                           prompt:@"pollen grain with spiky exine"
                                           detail:@"Spiky exine · non-conductive"
                                        variation:1101
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"diatom-frustule"
                                             name:@"Diatom frustule"
                                         category:@"BIOLOGICAL"
                                           prompt:@"diatom frustule with porous silica shell"
                                           detail:@"Porous silica shell"
                                        variation:1102
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"fractured-titanium"
                                             name:@"Fractured titanium"
                                         category:@"MATERIALS"
                                           prompt:@"fractured titanium alloy surface"
                                           detail:@"Conductive metal fracture"
                                        variation:1103
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"microchip-traces"
                                             name:@"Microchip traces"
                                         category:@"MATERIALS"
                                           prompt:@"integrated circuit microchip traces"
                                           detail:@"Planar circuitry"
                                        variation:1104
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"volcanic-ash"
                                             name:@"Volcanic ash"
                                         category:@"GEOLOGICAL"
                                           prompt:@"volcanic ash powder particles"
                                           detail:@"Angular glass particles"
                                        variation:1105
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"salt-crystals"
                                             name:@"Salt crystals"
                                         category:@"GEOLOGICAL"
                                           prompt:@"salt crystal facets"
                                           detail:@"Cubic halite facets"
                                        variation:1106
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"carbon-fiber"
                                             name:@"Carbon fiber"
                                         category:@"MATERIALS"
                                           prompt:@"carbon fiber composite"
                                           detail:@"Woven conductive fibers"
                                        variation:1107
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"tissue-section"
                                             name:@"Tissue section"
                                         category:@"BIOLOGICAL"
                                           prompt:@"biological tissue section"
                                           detail:@"Soft biological surface"
                                        variation:1108
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"bone-trabeculae"
                                             name:@"Bone trabeculae"
                                         category:@"BIOLOGICAL"
                                           prompt:@"bone tissue surface"
                                           detail:@"Mineralized trabecular network"
                                        variation:1109
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"quartz-sand"
                                             name:@"Quartz sand"
                                         category:@"GEOLOGICAL"
                                           prompt:@"quartz sand grains"
                                           detail:@"Rounded silicate grains"
                                        variation:1110
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"rusted-steel"
                                             name:@"Rusted steel"
                                         category:@"MATERIALS"
                                           prompt:@"rusted steel surface"
                                           detail:@"Corrosion product layer"
                                        variation:1111
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"sponge-spicule"
                                             name:@"Sponge spicule"
                                         category:@"BIOLOGICAL"
                                           prompt:@"sponge spicule fibrous structure"
                                           detail:@"Siliceous fiber"
                                        variation:1112
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"foraminifera"
                                             name:@"Foraminifera"
                                         category:@"GEOLOGICAL"
                                           prompt:@"foraminifera calcite shell"
                                           detail:@"Chambered calcite shell"
                                        variation:1113
                                 recipeDictionary:nil],
        [[SpecimenPreset alloc] initWithIdentifier:@"butterfly-wing"
                                             name:@"Butterfly wing"
                                         category:@"BIOLOGICAL"
                                           prompt:@"butterfly wing scales"
                                           detail:@"Overlapping scales"
                                        variation:1114
                                 recipeDictionary:nil],
    ];
}

+ (NSArray<SpecimenPreset *> *)builtInModels {
    static NSArray<SpecimenPreset *> *models;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<SpecimenPreset *> *bundled = [self modelsFromBundledJSON];
        models = bundled.count > 0 ? bundled : [self fallbackPresets];
    });
    return models;
}

+ (NSArray<SpecimenPreset *> *)savedModels {
    return [SavedSpecimenStore sharedStore].savedPresets;
}

+ (NSArray<SpecimenPreset *> *)offlineModels {
    NSMutableArray<SpecimenPreset *> *models = [[self builtInModels] mutableCopy];
    [models addObjectsFromArray:[self savedModels]];
    return models;
}

+ (NSArray<SpecimenPreset *> *)offlinePresets {
    return [self builtInModels];
}

@end
