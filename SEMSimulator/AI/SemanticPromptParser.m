#import "SemanticPromptParser.h"
#import "AISampleRecipe.h"

@implementation SemanticPromptParser

+ (NSUInteger)seedForPrompt:(NSString *)prompt variation:(NSUInteger)variation {
    uint32_t hash = 2166136261u;
    const char *bytes = prompt.UTF8String;
    while (bytes && *bytes) {
        hash ^= (uint8_t)*bytes++;
        hash *= 16777619u;
    }
    hash ^= (uint32_t)variation;
    hash *= 16777619u;
    return hash;
}

+ (AISampleRecipe *)recipeForPrompt:(NSString *)prompt variation:(NSUInteger)variation {
    NSString *lower = prompt.lowercaseString ?: @"";
    AISampleRecipe *r = [[AISampleRecipe alloc] init];
    r.seed = [self seedForPrompt:prompt variation:variation];
    r.name = prompt.length > 0 ? prompt : @"Specimen";
    r.scaleMicrometers = 50;
    r.meanZ = 14;
    r.conductive = NO;
    r.coatingRecommended = YES;
    r.spikes = 0.18;
    r.pores = 0.22;
    r.roughness = 0.45;
    r.cracks = 0.20;
    r.fibers = 0.05;
    r.grain = 0.40;

    BOOL (^has)(NSString *) = ^BOOL(NSString *needle) {
        return [lower rangeOfString:needle].location != NSNotFound;
    };
    BOOL (^word)(NSString *) = ^BOOL(NSString *needle) {
        NSString *pattern = [NSString stringWithFormat:@"\\b%@\\b", needle];
        return [lower rangeOfString:pattern options:NSRegularExpressionSearch].location != NSNotFound;
    };

    if (has(@"pollen") || has(@"spore") || has(@"exine")) {
        r.templateName = @"pollen";
        r.name = prompt.length > 0 ? prompt : @"Pollen grain with spiky exine";
        r.spikes = 0.82;
        r.pores = 0.55;
        r.roughness = 0.35;
        r.meanZ = 7.2;
        r.conductive = NO;
        r.coatingRecommended = YES;
        r.scaleMicrometers = 80;
    } else if (has(@"diatom") || has(@"frustule") || has(@"silica shell") || has(@"foram") || has(@"calcite") || has(@"chamber")) {
        r.templateName = has(@"foram") || has(@"calcite") || has(@"chamber") ? @"foram" : @"diatom";
        r.name = prompt.length > 0 ? prompt : @"Diatom frustule";
        r.pores = has(@"foram") ? 0.72 : 0.88;
        r.spikes = 0.12;
        r.roughness = 0.28;
        r.meanZ = 11.0;
        r.scaleMicrometers = has(@"foram") ? 180 : 60;
    } else if (has(@"bone") || has(@"trabecul")) {
        r.templateName = @"bone";
        r.name = prompt.length > 0 ? prompt : @"Bone trabeculae";
        r.pores = 0.65;
        r.spikes = 0.0;
        r.roughness = 0.38;
        r.meanZ = 13.0;
        r.conductive = NO;
        r.coatingRecommended = YES;
        r.scaleMicrometers = 90;
    } else if (has(@"wing") || has(@"scale")) {
        r.templateName = @"wing";
        r.name = prompt.length > 0 ? prompt : @"Butterfly wing scales";
        r.pores = 0.12;
        r.spikes = 0.08;
        r.roughness = 0.30;
        r.fibers = 0.30;
        r.meanZ = 8.0;
        r.conductive = NO;
        r.coatingRecommended = YES;
        r.scaleMicrometers = 70;
    } else if (has(@"chip") || has(@"circuit") || has(@"microchip") || has(@"trace") || has(@"semiconductor")) {
        r.templateName = @"circuit";
        r.name = prompt.length > 0 ? prompt : @"Integrated circuit microchip traces";
        r.spikes = 0.0;
        r.pores = 0.05;
        r.roughness = 0.18;
        r.cracks = 0.10;
        r.grain = 0.20;
        r.meanZ = 16.0;
        r.conductive = NO;
        r.coatingRecommended = YES;
        r.scaleMicrometers = 200;
    } else if (has(@"fiber") || has(@"fibre") || has(@"fibrous") || has(@"hair") || has(@"wire") || has(@"spicule") || has(@"siliceous") || has(@"silk")) {
        r.templateName = @"fiber";
        r.name = prompt.length > 0 ? prompt : @"Fibrous composite";
        r.fibers = 0.85;
        r.roughness = 0.50;
        r.meanZ = 9.0;
        r.scaleMicrometers = has(@"spicule") ? 120 : 150;
    } else if (has(@"powder") || has(@"particle") || has(@"ash") || has(@"granul") || has(@"sand") || has(@"quartz")) {
        r.templateName = @"powder";
        r.name = prompt.length > 0 ? prompt : @"Powder particles";
        r.grain = 0.85;
        r.pores = has(@"sand") || has(@"quartz") ? 0.16 : 0.35;
        r.roughness = has(@"sand") || has(@"quartz") ? 0.42 : 0.60;
        r.meanZ = 14.0;
        r.scaleMicrometers = has(@"sand") || has(@"quartz") ? 220 : 100;
    } else if (has(@"crystal") || has(@"mineral") || has(@"facet") || has(@"salt")) {
        r.templateName = @"crystal";
        r.name = prompt.length > 0 ? prompt : @"Crystal facets";
        r.grain = 0.72;
        r.roughness = 0.32;
        r.meanZ = 18.0;
        r.scaleMicrometers = 120;
    } else if (has(@"tissue") || has(@"cell") || has(@"biological") || has(@"bacteria") || has(@"virus")) {
        r.templateName = @"tissue";
        r.name = prompt.length > 0 ? prompt : @"Biological tissue";
        r.pores = 0.42;
        r.roughness = 0.42;
        r.meanZ = 6.5;
        r.scaleMicrometers = 50;
    } else if (word(@"insect") || word(@"bug") || word(@"arthropod") || word(@"fly") || word(@"ant") ||
               word(@"bee") || word(@"wasp") || word(@"mite") || word(@"tick") || word(@"flea") ||
               word(@"cricket") || word(@"aphid") || has(@"dragonfly") || has(@"housefly") ||
               has(@"firefly") || has(@"butterfly") || has(@"beetle") || has(@"moth") ||
               has(@"spider") || has(@"arachnid") || has(@"ladybug") || has(@"weevil") ||
               has(@"grasshopper") || has(@"cockroach") || has(@"termite") || has(@"mosquito") ||
               has(@"centipede") || has(@"millipede") || has(@"scorpion")) {
        r.templateName = @"insect";
        r.name = prompt.length > 0 ? prompt : @"House fly";
        r.spikes = 0.10;
        r.pores = 0.10;
        r.roughness = 0.38;
        r.cracks = 0.05;
        r.fibers = 0.0;
        r.grain = 0.25;
        r.meanZ = 7.0;
        r.conductive = NO;
        r.coatingRecommended = YES;
        r.scaleMicrometers = 800;
        if (word(@"ant") || has(@"beetle") || has(@"ladybug") || has(@"weevil")) {
            r.scaleMicrometers = 300;
        } else if (has(@"spider") || has(@"arachnid") || word(@"mite") || word(@"tick")) {
            r.scaleMicrometers = 200;
        } else if (has(@"butterfly") || has(@"moth")) {
            r.scaleMicrometers = 900;
        }
    } else {
        BOOL corroded = has(@"rust") || has(@"steel") || has(@"corrosion");
        r.templateName = @"fracture";
        r.name = prompt.length > 0 ? prompt : @"Fractured titanium alloy surface";
        r.cracks = has(@"fracture") || has(@"crack") || has(@"broken") || has(@"alloy") || has(@"metal") ? 0.88 : 0.62;
        r.roughness = corroded ? 0.78 : 0.65;
        r.pores = corroded ? 0.52 : r.pores;
        r.meanZ = has(@"titanium") ? 22.0 : 20.0;
        r.conductive = YES;
        r.coatingRecommended = NO;
        r.scaleMicrometers = corroded ? 65 : 40;
    }

    if (has(@"smooth") || has(@"polished")) {
        r.roughness = 0.18;
        r.spikes = MIN(r.spikes, 0.12);
    }
    if (has(@"rough") || has(@"jagged")) r.roughness = MAX(r.roughness, 0.72);
    if (has(@"porous") || has(@"pore")) r.pores = MAX(r.pores, 0.78);
    if (has(@"spiky") || has(@"spike")) r.spikes = MAX(r.spikes, 0.78);
    if (has(@"layered") || has(@"fibrous")) r.fibers = MAX(r.fibers, 0.75);
    if (has(@"gold") || has(@"coated")) r.coatingRecommended = YES;

    return r;
}

@end
