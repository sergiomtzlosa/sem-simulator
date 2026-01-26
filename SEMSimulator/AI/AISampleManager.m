#import "AISampleManager.h"
#import "AISampleRecipe.h"
#import "OpenCodeIntegration.h"
#import "ProceduralSampleGenerator.h"
#import "SemanticPromptParser.h"
#import "SpecimenLibrary.h"
#import "SEMSpecimen.h"

@implementation AISampleManager {
    ProceduralSampleGenerator *_generator;
    dispatch_queue_t _generationQueue;
    NSString *_lastGenerationNote;
}

- (instancetype)initWithDevice:(id<MTLDevice>)device {
    self = [super init];
    if (self) {
        _generator = [[ProceduralSampleGenerator alloc] initWithDevice:device];
        _generationQueue = dispatch_queue_create("com.semsimulator.sample-generation", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)generateSpecimenWithRecipe:(AISampleRecipe *)recipe
                        completion:(void (^)(SEMSpecimen * _Nullable, NSError * _Nullable))completion {
    [self generateSpecimenWithRecipe:recipe sourcePrompt:nil completion:completion];
}

- (void)generateSpecimenWithRecipe:(AISampleRecipe *)recipe
                      sourcePrompt:(nullable NSString *)sourcePrompt
                        completion:(void (^)(SEMSpecimen * _Nullable, NSError * _Nullable))completion {
    if (!recipe) {
        NSError *error = [NSError errorWithDomain:@"SEM.Specimen"
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: @"No specimen recipe was supplied."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, error);
        });
        return;
    }

    dispatch_async(_generationQueue, ^{
        NSError *error = nil;
        SEMSpecimen *specimen = [self->_generator generateSpecimenWithRecipe:recipe error:&error];
        specimen.sourcePrompt = sourcePrompt;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(specimen, specimen ? nil : error);
        });
    });
}

- (void)generateSpecimenForPrompt:(NSString *)prompt
                        variation:(NSUInteger)variation
                       completion:(void (^)(SEMSpecimen * _Nullable, NSError * _Nullable))completion {
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:prompt variation:variation];
    [self generateSpecimenWithRecipe:recipe sourcePrompt:prompt completion:completion];
}

- (void)generateSpecimenForPreset:(SpecimenPreset *)preset
                       completion:(void (^)(SEMSpecimen * _Nullable, NSError * _Nullable))completion {
    AISampleRecipe *recipe = [preset recipeRepresentation];
    if (!recipe) {
        NSError *error = [NSError errorWithDomain:@"SEM.Specimen"
                                             code:5
                                         userInfo:@{NSLocalizedDescriptionKey: @"The built-in model recipe is invalid."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, error);
        });
        return;
    }
    [self generateSpecimenWithRecipe:recipe sourcePrompt:preset.prompt completion:completion];
}

- (NSString *)recipePromptForDescription:(NSString *)description {
    return [NSString stringWithFormat:
            @"You generate specimen recipes for a scanning electron microscope simulator.\n"
            @"Return ONLY one compact JSON object. No markdown, no code fences, no explanation.\n"
            @"Use exactly this structure:\n"
            @"{\"name\":\"short name\",\"template\":\"pollen\",\"features\":{\"spikes\":0.5,\"pores\":0.3,\"roughness\":0.4,\"cracks\":0.2,\"fibers\":0.1,\"grain\":0.3},\"material\":{\"meanZ\":14,\"conductive\":false,\"coatingRecommended\":true},\"scaleUm\":50}\n"
            @"Rules:\n"
            @"- template must be exactly one of: pollen, diatom, circuit, powder, crystal, fiber, tissue, fracture, bone, foram, wing.\n"
            @"- Choose the closest template for the specimen description.\n"
            @"- Metals, alloys, rusted steel, and fractured hard surfaces must use template \"fracture\", conductive true, coatingRecommended false.\n"
            @"- Biological, polymer, ceramic, and mineral specimens are usually non-conductive; set coatingRecommended true.\n"
            @"- features values must be numbers from 0 to 1.\n"
            @"- meanZ must be a number from 1 to 92. Use an approximate atomic number: carbon 6, oxygen 8, aluminum 13, silicon 14, titanium 22, iron 26, copper 29.\n"
            @"- conductive must be true for metals and false for biological or insulating specimens.\n"
            @"- coatingRecommended must be true when the specimen is non-conductive.\n"
            @"- scaleUm must be a number from 1 to 1000.\n"
            @"- name must be a short specimen name of at most 6 words.\n"
            @"Examples:\n"
            @"Description: fractured titanium alloy -> {\"name\":\"Ti alloy fracture\",\"template\":\"fracture\",\"features\":{\"spikes\":0,\"pores\":0.1,\"roughness\":0.5,\"cracks\":0.8,\"fibers\":0,\"grain\":0.4},\"material\":{\"meanZ\":22,\"conductive\":true,\"coatingRecommended\":false},\"scaleUm\":20}\n"
            @"Description: pollen grain -> {\"name\":\"Pollen grain\",\"template\":\"pollen\",\"features\":{\"spikes\":0.8,\"pores\":0.5,\"roughness\":0.3,\"cracks\":0.1,\"fibers\":0,\"grain\":0.2},\"material\":{\"meanZ\":7,\"conductive\":false,\"coatingRecommended\":true},\"scaleUm\":80}\n"
            @"Specimen description: %@",
            description];
}

- (void)generateSpecimenUsingOpenCodeForPrompt:(NSString *)prompt
                                     variation:(NSUInteger)variation
                                    completion:(void (^)(SEMSpecimen * _Nullable, NSError * _Nullable))completion {
    _lastGenerationNote = nil;

    NSString *description = [prompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (description.length == 0) {
        NSError *error = [NSError errorWithDomain:@"SEM.Specimen"
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Enter a specimen description first."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) completion(nil, error);
        });
        return;
    }

    NSString *recipePrompt = [self recipePromptForDescription:description];
    [OpenCodeIntegration generateTextWithPrompt:recipePrompt model:nil completion:^(NSString * _Nullable text, NSInteger status, NSError * _Nullable error) {
        if (text.length == 0) {
            NSString *note = nil;
            if (status == 429) {
                note = @"OPENCODE RATE LIMITED - LOCAL RECIPE";
            } else if (status == 401 || status == 403) {
                note = @"OPENCODE AUTH FAILED - LOCAL RECIPE";
            } else if (error || status == 0 || status >= 500) {
                note = @"OPENCODE UNAVAILABLE - LOCAL RECIPE";
            } else {
                note = @"OPENCODE ERROR - LOCAL RECIPE";
            }
            [self fallbackToLocalRecipeForPrompt:description
                                       variation:variation
                                            note:note
                                      completion:completion];
            return;
        }

        NSError *parseError = nil;
        AISampleRecipe *recipe = [AISampleRecipe recipeFromJSONText:text fallbackName:description error:&parseError];
        if (!recipe) {
            [self fallbackToLocalRecipeForPrompt:description
                                       variation:variation
                                            note:@"OPENCODE INVALID RECIPE - LOCAL RECIPE"
                                      completion:completion];
            return;
        }
        recipe.seed = variation;
        if (recipe.name.length == 0) recipe.name = description;

        [self generateSpecimenWithRecipe:recipe sourcePrompt:description completion:completion];
    }];
}

- (void)fallbackToLocalRecipeForPrompt:(NSString *)prompt
                             variation:(NSUInteger)variation
                                  note:(NSString *)note
                            completion:(void (^)(SEMSpecimen * _Nullable, NSError * _Nullable))completion {
    _lastGenerationNote = [note copy];
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:prompt variation:variation];
    [self generateSpecimenWithRecipe:recipe sourcePrompt:prompt completion:completion];
}

@end
