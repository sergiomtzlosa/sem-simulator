#import "AISampleRecipe.h"

static double RecipeClamp(double v, double lo, double hi) { return MIN(MAX(v, lo), hi); }

static double RecipeNumber(id value, double fallback) {
    return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}

static BOOL RecipeBool(id value, BOOL fallback) {
    return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}

static NSError *RecipeError(NSString *message, NSInteger code) {
    return [NSError errorWithDomain:@"SEM.Specimen"
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation AISampleRecipe

+ (NSSet<NSString *> *)validTemplates {
    static NSSet *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"pollen", @"fracture", @"diatom", @"circuit", @"powder", @"crystal", @"fiber", @"tissue", @"foram", @"bone", @"wing"]];
    });
    return set;
}

+ (NSString *)normalizedTemplateName:(NSString *)rawValue {
    NSString *value = [[rawValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
    if (value.length == 0) return @"fracture";
    if ([[self validTemplates] containsObject:value]) return value;

    NSArray<NSArray<NSString *> *> *synonyms = @[
        @[@"pollen", @"pollen"], @[@"spore", @"pollen"], @[@"exine", @"pollen"], @[@"seed", @"pollen"],
        @[@"diatom", @"diatom"], @[@"frustule", @"diatom"], @[@"silica", @"diatom"],
        @[@"circuit", @"circuit"], @[@"microchip", @"circuit"], @[@"semiconductor", @"circuit"], @[@"chip", @"circuit"], @[@"trace", @"circuit"],
        @[@"powder", @"powder"], @[@"particle", @"powder"], @[@"sand", @"powder"], @[@"ash", @"powder"], @[@"granul", @"powder"],
        @[@"crystal", @"crystal"], @[@"mineral", @"crystal"], @[@"salt", @"crystal"], @[@"facet", @"crystal"],
        @[@"fiber", @"fiber"], @[@"fibre", @"fiber"], @[@"textile", @"fiber"], @[@"fabric", @"fiber"], @[@"carbon", @"fiber"],
        @[@"tissue", @"tissue"], @[@"cell", @"tissue"], @[@"bio", @"tissue"], @[@"bacteria", @"tissue"],
        @[@"bone", @"bone"], @[@"trabecul", @"bone"],
        @[@"foram", @"foram"], @[@"shell", @"foram"], @[@"marine", @"foram"], @[@"calcite", @"foram"],
        @[@"wing", @"wing"], @[@"butterfly", @"wing"], @[@"insect", @"wing"], @[@"scale", @"wing"],
        @[@"fracture", @"fracture"], @[@"crack", @"fracture"], @[@"metal", @"fracture"], @[@"alloy", @"fracture"],
        @[@"steel", @"fracture"], @[@"rust", @"fracture"], @[@"ceramic", @"fracture"]
    ];
    for (NSArray<NSString *> *pair in synonyms) {
        if ([value containsString:pair[0]]) return pair[1];
    }
    return @"fracture";
}

+ (nullable instancetype)recipeFromDictionary:(NSDictionary *)dictionary error:(NSError **)error {
    if (![dictionary isKindOfClass:[NSDictionary class]]) {
        if (error) *error = RecipeError(@"Specimen recipe was not a JSON object.", 1);
        return nil;
    }
    AISampleRecipe *recipe = [[AISampleRecipe alloc] init];

    NSString *name = [dictionary[@"name"] isKindOfClass:[NSString class]] ? dictionary[@"name"] : @"Specimen";
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    recipe.name = name.length > 0 ? name : @"Specimen";

    id templateValue = dictionary[@"template"];
    if (![templateValue isKindOfClass:[NSString class]]) templateValue = dictionary[@"templateName"];
    NSString *templateName = [templateValue isKindOfClass:[NSString class]] ? templateValue : @"fracture";
    recipe.templateName = [self normalizedTemplateName:templateName];

    NSDictionary *features = [dictionary[@"features"] isKindOfClass:[NSDictionary class]] ? dictionary[@"features"] : dictionary;
    recipe.spikes = RecipeClamp(RecipeNumber(features[@"spikes"], 0), 0, 1);
    recipe.pores = RecipeClamp(RecipeNumber(features[@"pores"], 0), 0, 1);
    recipe.roughness = RecipeClamp(RecipeNumber(features[@"roughness"], 0), 0, 1);
    recipe.cracks = RecipeClamp(RecipeNumber(features[@"cracks"], 0), 0, 1);
    recipe.fibers = RecipeClamp(RecipeNumber(features[@"fibers"], 0), 0, 1);
    recipe.grain = RecipeClamp(RecipeNumber(features[@"grain"], 0), 0, 1);

    NSDictionary *material = [dictionary[@"material"] isKindOfClass:[NSDictionary class]] ? dictionary[@"material"] : dictionary;
    double meanZ = RecipeNumber(material[@"meanZ"], 14);
    if (meanZ <= 0) meanZ = 14;
    recipe.meanZ = RecipeClamp(meanZ, 1, 92);
    recipe.conductive = RecipeBool(material[@"conductive"], NO);
    recipe.coatingRecommended = RecipeBool(material[@"coatingRecommended"], !recipe.conductive);

    recipe.seed = (NSUInteger)MAX(0.0, RecipeNumber(dictionary[@"seed"], 0));

    double scale = RecipeNumber(dictionary[@"scaleUm"], 0);
    if (scale <= 0) scale = RecipeNumber(dictionary[@"scaleMicrometers"], 50);
    if (scale <= 0) scale = 50;
    recipe.scaleMicrometers = RecipeClamp(scale, 1, 1000);
    return recipe;
}

+ (nullable instancetype)recipeFromJSONText:(NSString *)text
                               fallbackName:(NSString *)fallbackName
                                      error:(NSError **)error {
    if (![text isKindOfClass:[NSString class]] || text.length == 0) {
        if (error) *error = RecipeError(@"OpenCode returned an empty specimen recipe.", 2);
        return nil;
    }

    NSString *clean = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([clean hasPrefix:@"```"]) {
        NSRange firstNewline = [clean rangeOfString:@"\n"];
        if (firstNewline.location != NSNotFound) {
            clean = [clean substringFromIndex:firstNewline.location + firstNewline.length];
        }
        if ([clean hasSuffix:@"```"]) {
            clean = [clean substringToIndex:clean.length - 3];
        }
        clean = [clean stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }

    NSRange start = [clean rangeOfString:@"{"];
    NSRange end = [clean rangeOfString:@"}" options:NSBackwardsSearch];
    if (start.location == NSNotFound || end.location == NSNotFound || end.location <= start.location) {
        if (error) *error = RecipeError(@"OpenCode did not return a JSON specimen recipe.", 2);
        return nil;
    }

    NSString *jsonText = [clean substringWithRange:NSMakeRange(start.location, end.location - start.location + 1)];
    NSData *data = [jsonText dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    id object = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError] : nil;
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error) {
            *error = RecipeError(jsonError.localizedDescription ?: @"OpenCode returned invalid specimen JSON.", 2);
        }
        return nil;
    }

    AISampleRecipe *recipe = [self recipeFromDictionary:object error:error];
    if (!recipe) return nil;

    NSString *fallback = [fallbackName stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (fallback.length > 0 &&
        (recipe.name.length == 0 || [recipe.name caseInsensitiveCompare:@"Specimen"] == NSOrderedSame)) {
        recipe.name = fallback;
    }
    if (recipe.name.length > 80) {
        recipe.name = [[recipe.name substringToIndex:80] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return recipe;
}

- (NSDictionary *)dictionaryRepresentation {
    return @{
        @"name": self.name ?: @"Specimen",
        @"template": self.templateName ?: @"fracture",
        @"features": @{
            @"spikes": @(self.spikes),
            @"pores": @(self.pores),
            @"roughness": @(self.roughness),
            @"cracks": @(self.cracks),
            @"fibers": @(self.fibers),
            @"grain": @(self.grain)
        },
        @"material": @{
            @"meanZ": @(self.meanZ),
            @"conductive": @(self.conductive),
            @"coatingRecommended": @(self.coatingRecommended)
        },
        @"seed": @(self.seed),
        @"scaleUm": @(self.scaleMicrometers)
    };
}

@end
