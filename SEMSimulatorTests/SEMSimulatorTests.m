#import <XCTest/XCTest.h>
#import <Metal/Metal.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>

#import "SEMPhysicsEngine.h"
#import "SEMScaleMath.h"
#import "SEMSpecimen.h"
#import "SemanticPromptParser.h"
#import "AISampleRecipe.h"
#import "AISampleManager.h"
#import "MetalCRTView.h"
#import "OpenCodeIntegration.h"
#import "SavedSpecimenStore.h"
#import "SettingsWindowController.h"
#import "SpecimenLibrary.h"
#import "AISampleDrawer.h"
#import "ConsoleView.h"
#import "HelpWindowController.h"
#import "LEDIndicatorView.h"
#import "MainWindowController.h"
#import "PanelView.h"
#import "PressureGaugeView.h"
#import "RockerSwitchControl.h"
#import "RotaryKnobControl.h"
#import "Theme.h"
#import "VoltageSelectorView.h"

static void SEMAdvance(SEMPhysicsEngine *engine, NSTimeInterval seconds) {
    const NSTimeInterval step = 0.25;
    NSInteger ticks = (NSInteger)ceil(seconds / step);
    for (NSInteger index = 0; index < ticks; index++) {
        [engine tick:step];
    }
}

@interface OpenCodeIntegration (SEMTesting)
+ (NSArray<NSDictionary<NSString *, id> *> *)modelCandidatesFromJSON:(NSDictionary *)json;
@end

@interface SEMSimulatorTests : XCTestCase
@end

@implementation SEMSimulatorTests

#pragma mark - Vacuum sequence

- (void)testInitialVacuumStateIsVented {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVented);
    XCTAssertFalse(engine.vacuumReady);
    XCTAssertFalse(engine.roughingPumpOn);
    XCTAssertFalse(engine.diffusionPumpOn);
    XCTAssertFalse(engine.highVoltageOn);
    XCTAssertFalse(engine.beamOn);
    XCTAssertGreaterThan(engine.pressurePa, 100000.0);
}

- (void)testEvacSequenceReachesHighVacuum {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];

    XCTAssertTrue(engine.roughingPumpOn);
    XCTAssertTrue(engine.autoHighVoltage);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateRoughing);

    SEMAdvance(engine, 100.0);

    XCTAssertEqual(engine.vacuumState, SEMVacuumStateHighVacuum);
    XCTAssertTrue(engine.diffusionPumpOn);
    XCTAssertTrue(engine.vacuumReady);
    XCTAssertFalse(engine.fault);
    XCTAssertLessThan(engine.pressurePa, 5.0e-3);
    XCTAssertTrue(engine.highVoltageOn);
    XCTAssertTrue(engine.beamOn);
    XCTAssertFalse(engine.autoHighVoltage);
    XCTAssertEqualObjects(engine.statusMessage, @"HIGH VACUUM READY - HV ON");
}

- (void)testEvacAutomaticallyTurnsOnHighVoltage {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];

    SEMAdvance(engine, 45.0);

    XCTAssertTrue(engine.vacuumReady);
    XCTAssertTrue(engine.highVoltageOn);
    XCTAssertTrue(engine.beamOn);
    XCTAssertFalse(engine.autoHighVoltage);
}

- (void)testEvacDuringWarmupDoesNotRestartDiffusionPump {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];
    SEMAdvance(engine, 25.0);

    XCTAssertTrue(engine.diffusionPumpOn);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateDPWarmup);
    double remaining = engine.dpWarmupRemaining;
    XCTAssertGreaterThan(remaining, 0.0);

    [engine evac];

    XCTAssertEqualWithAccuracy(engine.dpWarmupRemaining, remaining, 0.001);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateDPWarmup);
}

- (void)testVentCancelsAutomaticHighVoltage {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];
    SEMAdvance(engine, 45.0);
    XCTAssertTrue(engine.highVoltageOn);

    [engine vent];

    XCTAssertFalse(engine.autoHighVoltage);
    XCTAssertFalse(engine.highVoltageOn);
    SEMAdvance(engine, 20.0);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVented);
    XCTAssertFalse(engine.highVoltageOn);
}

- (void)testHighVoltageInterlockWhileVented {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine setHighVoltageOn:YES];

    XCTAssertFalse(engine.highVoltageOn);
    XCTAssertFalse(engine.beamOn);
    XCTAssertEqualObjects(engine.statusMessage, @"HV INTERLOCK: VACUUM NOT READY");
}

- (void)testHighVoltageTurnsOnAtHighVacuum {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];
    SEMAdvance(engine, 100.0);

    [engine setHighVoltageOn:YES];

    XCTAssertTrue(engine.highVoltageOn);
    XCTAssertTrue(engine.beamOn);
    XCTAssertEqualObjects(engine.statusMessage, @"HIGH VOLTAGE ON");
}

- (void)testVentingForcesHighVoltageOff {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];
    SEMAdvance(engine, 100.0);
    [engine setHighVoltageOn:YES];
    XCTAssertTrue(engine.beamOn);

    [engine vent];

    XCTAssertFalse(engine.highVoltageOn);
    XCTAssertFalse(engine.beamOn);
    XCTAssertFalse(engine.roughingPumpOn);
    XCTAssertFalse(engine.diffusionPumpOn);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVenting);

    SEMAdvance(engine, 20.0);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVented);
}

- (void)testDiffusionPumpRequiresRoughVacuum {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine setDiffusionPumpOn:YES];

    XCTAssertFalse(engine.diffusionPumpOn);
    XCTAssertEqualObjects(engine.statusMessage, @"DP INTERLOCK: ROUGH VACUUM REQUIRED");
}

- (void)testVentAfterHighVacuumDoesNotFault {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine evac];
    SEMAdvance(engine, 100.0);
    [engine vent];

    SEMAdvance(engine, 25.0);

    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVented);
    XCTAssertFalse(engine.fault);
}

- (void)testResetFaultRestoresVentedState {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    [engine resetFault];

    XCTAssertFalse(engine.fault);
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVented);
    XCTAssertEqualObjects(engine.statusMessage, @"FAULT RESET");
}

#pragma mark - Optics

- (void)testAcceleratingVoltageSnapsToSteps {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];

    [engine setAcceleratingVoltageKV:12];
    XCTAssertEqual(engine.acceleratingVoltageKV, 10);

    [engine setAcceleratingVoltageKV:13];
    XCTAssertEqual(engine.acceleratingVoltageKV, 15);

    [engine setAcceleratingVoltageKV:2];
    XCTAssertEqual(engine.acceleratingVoltageKV, 1);
}

- (void)testControlClamping {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];

    [engine setMagnification:1.0];
    XCTAssertEqualWithAccuracy(engine.magnification, 10.0, 0.0001);
    [engine setMagnification:1.0e9];
    XCTAssertEqualWithAccuracy(engine.magnification, 100000.0, 0.0001);

    [engine setWorkingDistanceMM:0.0];
    XCTAssertEqualWithAccuracy(engine.workingDistanceMM, 8.0, 0.0001);
    [engine setWorkingDistanceMM:100.0];
    XCTAssertEqualWithAccuracy(engine.workingDistanceMM, 48.0, 0.0001);

    [engine setStageX:-5.0];
    XCTAssertEqualWithAccuracy(engine.stageX, 0.0, 0.0001);
    [engine setStageX:50.0];
    XCTAssertEqualWithAccuracy(engine.stageX, 10.0, 0.0001);
}

- (void)testRotationWrapsToPositiveDegrees {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];

    [engine setRotation:-90.0];
    XCTAssertEqualWithAccuracy(engine.rotation, 270.0, 0.0001);

    [engine setRotation:450.0];
    XCTAssertEqualWithAccuracy(engine.rotation, 90.0, 0.0001);
}

- (void)testNonConductiveSpecimenChargesAndCoatingSuppressesIt {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    SEMSpecimen *specimen = [[SEMSpecimen alloc] init];
    specimen.name = @"Test insulator";
    specimen.conductive = NO;
    specimen.coatingRecommended = YES;
    engine.specimen = specimen;

    [engine evac];
    SEMAdvance(engine, 100.0);
    // Attach the specimen after the automatic EVAC/HV sequence so the charge
    // measurement starts from zero rather than accumulating during pump-down.
    engine.specimen = specimen;
    XCTAssertTrue(engine.beamOn);

    SEMAdvance(engine, 5.0);
    double uncoatedCharge = engine.charge;
    XCTAssertGreaterThan(uncoatedCharge, 0.01);

    // A gold coating slows charging by roughly 25x while the beam is on.
    [engine setGoldCoated:YES];
    SEMAdvance(engine, 5.0);
    double coatedCharge = engine.charge;
    XCTAssertGreaterThan(coatedCharge, uncoatedCharge);
    XCTAssertLessThan(coatedCharge - uncoatedCharge, 0.02);

    // With the beam off, the coating also lets the accumulated charge drain.
    [engine setHighVoltageOn:NO];
    SEMAdvance(engine, 5.0);
    XCTAssertLessThan(engine.charge, 0.01);
}

- (void)testLoadingSpecimenResetsCharge {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    SEMSpecimen *first = [[SEMSpecimen alloc] init];
    first.name = @"First";
    first.conductive = NO;
    engine.specimen = first;

    [engine evac];
    SEMAdvance(engine, 100.0);
    [engine setHighVoltageOn:YES];
    SEMAdvance(engine, 5.0);
    XCTAssertGreaterThan(engine.charge, 0.01);

    SEMSpecimen *second = [[SEMSpecimen alloc] init];
    second.name = @"Second";
    engine.specimen = second;

    XCTAssertEqualWithAccuracy(engine.charge, 0.0, 0.0001);
}

#pragma mark - Scale math

- (void)testFieldOfViewAtCommonMagnifications {
    XCTAssertEqualWithAccuracy([SEMScaleMath fieldOfViewMicrometersForMagnification:10], 10000.0, 0.001);
    XCTAssertEqualWithAccuracy([SEMScaleMath fieldOfViewMicrometersForMagnification:1000], 100.0, 0.001);
    XCTAssertEqualWithAccuracy([SEMScaleMath fieldOfViewMicrometersForMagnification:100000], 1.0, 0.001);
    XCTAssertEqualWithAccuracy([SEMScaleMath fieldOfViewMicrometersForMagnification:0], 100000.0, 0.001);
}

- (void)testNiceScaleBarUsesOneTwoFiveSequence {
    XCTAssertEqualWithAccuracy([SEMScaleMath niceScaleBarMicrometersForFieldOfView:100.0], 20.0, 1e-9);
    XCTAssertEqualWithAccuracy([SEMScaleMath niceScaleBarMicrometersForFieldOfView:10.0], 2.0, 1e-9);
    XCTAssertEqualWithAccuracy([SEMScaleMath niceScaleBarMicrometersForFieldOfView:1.0], 0.2, 1e-9);
}

- (void)testFormattingHelpers {
    XCTAssertEqualObjects([SEMScaleMath formatMagnification:1000.0], @"1,000x");
    XCTAssertEqualObjects([SEMScaleMath formatMicrometers:500.0], @"500 µm");
    XCTAssertEqualObjects([SEMScaleMath formatMicrometers:2500.0], @"2.5 mm");
    XCTAssertEqualObjects([SEMScaleMath formatMicrometers:0.5], @"500.00 nm");
    XCTAssertEqualObjects([SEMScaleMath formatPressurePa:101325.0 torr:NO], @"101325 Pa");
    XCTAssertEqualObjects([SEMScaleMath formatPressurePa:1.0e-4 torr:NO], @"1.00e-04 Pa");
    XCTAssertEqualObjects([SEMScaleMath voltageSteps], (@[@1, @5, @10, @15, @20, @25]));
}

#pragma mark - CRT zoom

- (void)testCRTViewZoomEasesTowardTarget {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        XCTSkip(@"Metal is unavailable on this machine.");
    }
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    MetalCRTView *view = [[MetalCRTView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64)
                                                      device:device
                                                      engine:engine];

    [view zoomByFactor:2.0];
    XCTAssertEqualWithAccuracy(engine.magnification, 1000.0, 0.001,
                               @"Zoom input should set a target, not jump immediately.");

    for (NSInteger index = 0; index < 120; index++) {
        [view drawFrame];
    }
    XCTAssertEqualWithAccuracy(engine.magnification, 2000.0, 1.0);
}

#pragma mark - Prompt parsing

- (void)testPollenPromptSelectsPollenTemplate {
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:@"pollen grain with spiky exine" variation:1];

    XCTAssertEqualObjects(recipe.templateName, @"pollen");
    XCTAssertGreaterThan(recipe.spikes, 0.7);
    XCTAssertTrue(recipe.coatingRecommended);
    XCTAssertFalse(recipe.conductive);
    XCTAssertEqualObjects(recipe.name, @"pollen grain with spiky exine");
}

- (void)testDiatomPromptSelectsDiatomTemplate {
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:@"diatom frustule" variation:2];

    XCTAssertEqualObjects(recipe.templateName, @"diatom");
    XCTAssertGreaterThan(recipe.pores, 0.8);
    XCTAssertEqualWithAccuracy(recipe.scaleMicrometers, 60.0, 0.001);
}

- (void)testMetalPromptIsConductive {
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:@"fractured titanium alloy" variation:3];

    XCTAssertEqualObjects(recipe.templateName, @"fracture");
    XCTAssertTrue(recipe.conductive);
    XCTAssertFalse(recipe.coatingRecommended);
    XCTAssertGreaterThan(recipe.cracks, 0.8);
    XCTAssertEqualWithAccuracy(recipe.meanZ, 22.0, 0.001);
}

- (void)testFeatureModifiersAdjustRecipe {
    AISampleRecipe *smooth = [SemanticPromptParser recipeForPrompt:@"smooth polished crystal" variation:4];
    XCTAssertEqualWithAccuracy(smooth.roughness, 0.18, 0.001);

    AISampleRecipe *porous = [SemanticPromptParser recipeForPrompt:@"porous rough ceramic" variation:5];
    XCTAssertGreaterThanOrEqual(porous.pores, 0.78);
    XCTAssertGreaterThanOrEqual(porous.roughness, 0.72);
}

- (void)testEmptyPromptFallsBackToFracture {
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:@"" variation:6];

    XCTAssertEqualObjects(recipe.templateName, @"fracture");
    XCTAssertEqualObjects(recipe.name, @"Fractured titanium alloy surface");
}

- (void)testRecipeSeedIsDeterministicForSamePromptAndVariation {
    AISampleRecipe *first = [SemanticPromptParser recipeForPrompt:@"powder particles" variation:42];
    AISampleRecipe *second = [SemanticPromptParser recipeForPrompt:@"powder particles" variation:42];
    AISampleRecipe *different = [SemanticPromptParser recipeForPrompt:@"powder particles" variation:43];

    XCTAssertEqual(first.seed, second.seed);
    XCTAssertNotEqual(first.seed, different.seed);
}

- (void)testRecipeDictionaryRoundTrip {
    AISampleRecipe *recipe = [SemanticPromptParser recipeForPrompt:@"fibrous composite" variation:7];
    NSDictionary *dictionary = [recipe dictionaryRepresentation];

    NSError *error = nil;
    AISampleRecipe *decoded = [AISampleRecipe recipeFromDictionary:dictionary error:&error];

    XCTAssertNotNil(decoded);
    XCTAssertNil(error);
    XCTAssertEqualObjects(decoded.name, recipe.name);
    XCTAssertEqualObjects(decoded.templateName, recipe.templateName);
    XCTAssertEqual(decoded.seed, recipe.seed);
    XCTAssertEqualWithAccuracy(decoded.roughness, recipe.roughness, 1e-9);
    XCTAssertEqualWithAccuracy(decoded.scaleMicrometers, recipe.scaleMicrometers, 1e-9);
    XCTAssertEqual(decoded.conductive, recipe.conductive);
}

- (void)testRecipeRejectsInvalidTemplate {
    NSDictionary *dictionary = @{
        @"name": @"Mystery",
        @"template": @"not-a-real-template",
        @"features": @{@"roughness": @2.0},
        @"material": @{@"meanZ": @500.0, @"conductive": @YES},
        @"scaleUm": @0
    };

    AISampleRecipe *recipe = [AISampleRecipe recipeFromDictionary:dictionary error:NULL];

    XCTAssertNotNil(recipe);
    XCTAssertEqualObjects(recipe.templateName, @"fracture");
    XCTAssertEqualWithAccuracy(recipe.roughness, 1.0, 1e-9);
    XCTAssertEqualWithAccuracy(recipe.meanZ, 92.0, 1e-9);
    XCTAssertEqualWithAccuracy(recipe.scaleMicrometers, 50.0, 1e-9);
}

- (void)testOpenCodeFencedJSONRecipeIsParsed {
    NSString *text = @"```json\n{\"name\":\"Specimen\",\"template\":\"semiconductor chip\",\"features\":{\"pores\":0.4,\"roughness\":0.6},\"material\":{\"meanZ\":18,\"conductive\":false,\"coatingRecommended\":true},\"seed\":9,\"scaleUm\":120}\n```";

    NSError *error = nil;
    AISampleRecipe *recipe = [AISampleRecipe recipeFromJSONText:text fallbackName:@"microchip traces" error:&error];

    XCTAssertNotNil(recipe);
    XCTAssertNil(error);
    XCTAssertEqualObjects(recipe.name, @"microchip traces");
    XCTAssertEqualObjects(recipe.templateName, @"circuit");
    XCTAssertEqualWithAccuracy(recipe.pores, 0.4, 1e-9);
    XCTAssertEqualWithAccuracy(recipe.roughness, 0.6, 1e-9);
    XCTAssertEqualWithAccuracy(recipe.meanZ, 18.0, 1e-9);
    XCTAssertEqual(recipe.seed, 9u);
    XCTAssertEqualWithAccuracy(recipe.scaleMicrometers, 120.0, 1e-9);
}

- (void)testOpenCodeJSONRecipeDefaultsMissingMaterial {
    NSString *text = @"{\"template\":\"unknown-material\",\"features\":{},\"material\":{}}";

    AISampleRecipe *recipe = [AISampleRecipe recipeFromJSONText:text fallbackName:nil error:NULL];

    XCTAssertNotNil(recipe);
    XCTAssertEqualObjects(recipe.name, @"Specimen");
    XCTAssertEqualObjects(recipe.templateName, @"fracture");
    XCTAssertEqualWithAccuracy(recipe.meanZ, 14.0, 1e-9);
    XCTAssertEqualWithAccuracy(recipe.scaleMicrometers, 50.0, 1e-9);
    XCTAssertFalse(recipe.conductive);
    XCTAssertTrue(recipe.coatingRecommended);
}

- (void)testOpenCodeJSONRecipeRejectsProseWithoutObject {
    NSError *error = nil;
    AISampleRecipe *recipe = [AISampleRecipe recipeFromJSONText:@"I cannot generate that specimen." fallbackName:nil error:&error];

    XCTAssertNil(recipe);
    XCTAssertNotNil(error);
}

#pragma mark - Built-in specimen models

- (void)testBuiltInModelCatalogIsPopulatedAndUnique {
    NSArray<SpecimenPreset *> *models = [SpecimenLibrary builtInModels];

    XCTAssertGreaterThanOrEqual(models.count, 14);
    XCTAssertEqualObjects(models, [SpecimenLibrary offlinePresets]);

    NSMutableSet<NSString *> *identifiers = [NSMutableSet set];
    NSMutableSet<NSString *> *names = [NSMutableSet set];
    NSMutableSet<NSString *> *prompts = [NSMutableSet set];
    for (SpecimenPreset *preset in models) {
        XCTAssertGreaterThan(preset.identifier.length, 0);
        XCTAssertGreaterThan(preset.name.length, 0);
        XCTAssertGreaterThan(preset.category.length, 0);
        XCTAssertGreaterThan(preset.prompt.length, 0);
        XCTAssertGreaterThan(preset.detail.length, 0);
        XCTAssertGreaterThan(preset.variation, 0);
        XCTAssertGreaterThan(preset.recipeDictionary.count, 0, @"Missing explicit recipe for %@", preset.name);
        XCTAssertFalse([identifiers containsObject:preset.identifier]);
        XCTAssertFalse([names containsObject:preset.name]);
        XCTAssertFalse([prompts containsObject:preset.prompt]);
        [identifiers addObject:preset.identifier];
        [names addObject:preset.name];
        [prompts addObject:preset.prompt];
    }
}

- (void)testSettingsBuiltInModelPopupListsCatalog {
    SettingsWindowController *controller = [[SettingsWindowController alloc] init];
    NSPopUpButton *popup = [controller valueForKey:@"builtInModelPopup"];
    XCTAssertTrue([popup isKindOfClass:[NSPopUpButton class]]);
    NSArray<SpecimenPreset *> *models = [SpecimenLibrary offlineModels];
    NSMutableArray<SpecimenPreset *> *popupModels = [NSMutableArray array];
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isKindOfClass:[SpecimenPreset class]]) {
            [popupModels addObject:item.representedObject];
        }
    }
    XCTAssertEqual(popupModels.count, models.count);
    for (NSInteger index = 0; index < popupModels.count; index++) {
        XCTAssertEqualObjects(popupModels[index].identifier, models[index].identifier);
    }
    XCTAssertNotNil([controller valueForKey:@"builtInDetailLabel"]);
    XCTAssertNotNil([controller valueForKey:@"builtInStatusLabel"]);
}

- (void)testBuiltInModelRecipesAreValidAndNamed {
    for (SpecimenPreset *preset in [SpecimenLibrary builtInModels]) {
        AISampleRecipe *recipe = [preset recipeRepresentation];
        XCTAssertNotNil(recipe, @"Could not build a recipe for %@", preset.name);
        XCTAssertEqualObjects(recipe.name, preset.name);
        XCTAssertEqual(recipe.seed, preset.variation);
        XCTAssertGreaterThanOrEqual(recipe.meanZ, 1.0);
        XCTAssertLessThanOrEqual(recipe.meanZ, 92.0);
        XCTAssertGreaterThanOrEqual(recipe.scaleMicrometers, 1.0);
        XCTAssertLessThanOrEqual(recipe.scaleMicrometers, 1000.0);
    }
}

- (void)testBuiltInModelGeneratesSpecimenOffline {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTAssertNotNil(device);
    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    SpecimenPreset *preset = [SpecimenLibrary builtInModels].firstObject;
    XCTAssertNotNil(preset);

    XCTestExpectation *expectation = [self expectationWithDescription:@"Built-in specimen generation"];
    [manager generateSpecimenForPreset:preset completion:^(SEMSpecimen *specimen, NSError *error) {
        XCTAssertNotNil(specimen, @"Built-in generation failed: %@", error);
        XCTAssertEqualObjects(specimen.name, preset.name);
        XCTAssertEqualObjects(specimen.templateName, [preset recipeRepresentation].templateName);
        XCTAssertNotNil(specimen.thumbnail);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];
}

- (void)testBuiltInModelRecipesSelectExpectedTemplates {
    NSDictionary<NSString *, NSString *> *expected = @{
        @"Pollen grain": @"pollen",
        @"Diatom frustule": @"diatom",
        @"Fractured titanium": @"fracture",
        @"Microchip traces": @"circuit",
        @"Volcanic ash": @"powder",
        @"Salt crystals": @"crystal",
        @"Carbon fiber": @"fiber",
        @"Tissue section": @"tissue",
        @"Bone trabeculae": @"bone",
        @"Quartz sand": @"powder",
        @"Rusted steel": @"fracture",
        @"Sponge spicule": @"fiber",
        @"Foraminifera": @"foram",
        @"Butterfly wing": @"wing"
    };

    for (SpecimenPreset *preset in [SpecimenLibrary builtInModels]) {
        NSString *templateName = expected[preset.name];
        XCTAssertNotNil(templateName, @"Missing expected template for model %@", preset.name);
        AISampleRecipe *recipe = [preset recipeRepresentation];
        XCTAssertEqualObjects(recipe.templateName, templateName, @"Unexpected template for model %@", preset.name);
    }
}

- (void)testNewTemplateNamesSurviveRecipeRoundTrip {
    for (NSString *templateName in @[@"bone", @"foram", @"wing"]) {
        NSDictionary *dictionary = @{
            @"name": templateName,
            @"template": templateName,
            @"features": @{@"roughness": @0.4},
            @"material": @{@"meanZ": @12.0, @"conductive": @NO},
            @"scaleUm": @80
        };
        AISampleRecipe *recipe = [AISampleRecipe recipeFromDictionary:dictionary error:NULL];
        XCTAssertEqualObjects(recipe.templateName, templateName);
    }
}

#pragma mark - OpenCode integration

- (void)testModelCandidatesPreferLocalThenFreeModels {
    NSDictionary *json = @{@"data": @[
        @{@"providerID": @"anthropic", @"id": @"claude", @"name": @"Claude", @"type": @"chat", @"enabled": @YES},
        @{@"providerID": @"opencode", @"id": @"deepseek-free", @"name": @"DeepSeek Free", @"type": @"chat", @"enabled": @YES},
        @{@"providerID": @"ollama", @"id": @"llama3.2:3b", @"name": @"Llama 3.2", @"type": @"chat", @"enabled": @YES},
        @{@"providerID": @"ollama", @"id": @"disabled", @"name": @"Disabled", @"type": @"chat", @"enabled": @NO},
        @{@"providerID": @"openai", @"id": @"image-model", @"name": @"Image", @"type": @"image", @"enabled": @YES}
    ]};

    NSArray<NSDictionary<NSString *, id> *> *candidates = [OpenCodeIntegration modelCandidatesFromJSON:json];

    XCTAssertEqual(candidates.count, 3);
    XCTAssertEqualObjects(candidates[0][@"identifier"], @"ollama/llama3.2:3b");
    XCTAssertTrue([candidates[0][@"local"] boolValue]);
    XCTAssertFalse([candidates[0][@"free"] boolValue]);
    XCTAssertEqualObjects(candidates[1][@"identifier"], @"opencode/deepseek-free");
    XCTAssertFalse([candidates[1][@"local"] boolValue]);
    XCTAssertTrue([candidates[1][@"free"] boolValue]);
    XCTAssertEqualObjects(candidates[2][@"identifier"], @"anthropic/claude");
}

- (void)testModelCandidatesIgnoreIncompleteEntries {
    NSDictionary *json = @{@"data": @[
        @{@"providerID": @"ollama", @"name": @"Missing ID"},
        @{@"id": @"missing-provider", @"name": @"Missing Provider"},
        @{@"providerID": @"ollama", @"id": @"llama3.2:3b", @"name": @"Llama 3.2"}
    ]};

    NSArray<NSDictionary<NSString *, id> *> *candidates = [OpenCodeIntegration modelCandidatesFromJSON:json];

    XCTAssertEqual(candidates.count, 1);
    XCTAssertEqualObjects(candidates.firstObject[@"identifier"], @"ollama/llama3.2:3b");
}

- (void)testOpenCodeModelListingIntegration {
    NSString *password = NSProcessInfo.processInfo.environment[@"SEM_OPENCODE_TEST_PASSWORD"];
    if (password.length == 0) {
        XCTSkip(@"Set SEM_OPENCODE_TEST_PASSWORD with a running OpenCode server to run this test.");
    }

    NSString *url = NSProcessInfo.processInfo.environment[@"SEM_OPENCODE_TEST_URL"] ?: SEMOpenCodeDefaultURL;
    XCTestExpectation *expectation = [self expectationWithDescription:@"OpenCode model listing"];

    [OpenCodeIntegration fetchAvailableModelsForURL:url password:password
                                         completion:^(NSArray<NSDictionary<NSString *, id> *> *models, NSError *error) {
        XCTAssertNotNil(models, @"OpenCode model listing failed: %@", error);
        XCTAssertGreaterThan(models.count, 0);
        XCTAssertGreaterThan([models.firstObject[@"identifier"] length], 0);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];
}

- (void)testOpenCodeModelListingWithoutAuth {
    NSString *url = NSProcessInfo.processInfo.environment[@"SEM_OPENCODE_TEST_EMPTY_URL"];
    if (url.length == 0) {
        XCTSkip(@"Set SEM_OPENCODE_TEST_EMPTY_URL to an unauthenticated stub server to run this test.");
    }

    XCTestExpectation *expectation = [self expectationWithDescription:@"OpenCode model listing without auth"];

    [OpenCodeIntegration fetchAvailableModelsForURL:url password:@""
                                         completion:^(NSArray<NSDictionary<NSString *, id> *> *models, NSError *error) {
        XCTAssertNotNil(models, @"Unauthenticated model listing failed: %@", error);
        XCTAssertEqualObjects(models.firstObject[@"identifier"], @"ollama/llama3.2:3b");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];
}

- (void)testOpenCodeFailureFallsBackToLocalRecipe {
    NSString *previousURL = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    [OpenCodeIntegration setServerURL:@"http://127.0.0.1:1"];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTAssertNotNil(device);
    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    XCTestExpectation *expectation = [self expectationWithDescription:@"local fallback generation"];

    [manager generateSpecimenUsingOpenCodeForPrompt:@"salt crystals"
                                          variation:99
                                         completion:^(SEMSpecimen *specimen, NSError *error) {
        XCTAssertNotNil(specimen, @"Fallback generation failed: %@", error);
        XCTAssertNil(error);
        XCTAssertGreaterThan(specimen.name.length, 0);
        XCTAssertGreaterThan(manager.lastGenerationNote.length, 0);
        XCTAssertTrue([manager.lastGenerationNote containsString:@"LOCAL RECIPE"]);
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:30 handler:nil];

    if (previousURL.length > 0) {
        [OpenCodeIntegration setServerURL:previousURL];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEMOpenCodeURLDefaultsKey];
    }
}

- (void)testOpenCodeSpecimenGenerationIntegration {
    NSString *enabled = NSProcessInfo.processInfo.environment[@"SEM_OPENCODE_INTEGRATION_TEST"];
    if (!enabled.boolValue) {
        XCTSkip(@"Set SEM_OPENCODE_INTEGRATION_TEST=1 with a running OpenCode server to run this test.");
    }

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTAssertNotNil(device);
    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    XCTestExpectation *expectation = [self expectationWithDescription:@"OpenCode specimen generation"];

    [manager generateSpecimenUsingOpenCodeForPrompt:@"fractured titanium alloy with fine cracks"
                                          variation:20261112
                                         completion:^(SEMSpecimen *specimen, NSError *error) {
        XCTAssertNotNil(specimen, @"OpenCode generation failed: %@", error);
        XCTAssertGreaterThan(specimen.name.length, 0);
        XCTAssertEqualObjects(specimen.templateName, @"fracture");
        [expectation fulfill];
    }];

    [self waitForExpectationsWithTimeout:180 handler:nil];
}

@end

#pragma mark - UI and integration test helpers

@interface SEMTestActionTarget : NSObject
@property (nonatomic, assign) NSInteger actionCount;
@property (nonatomic, strong, nullable) id lastSender;
- (void)actionFired:(id)sender;
@end

@implementation SEMTestActionTarget
- (void)actionFired:(id)sender {
    self.actionCount += 1;
    self.lastSender = sender;
}
@end

@interface SEMTestDrawerDelegate : NSObject <AISampleDrawerDelegate>
@property (nonatomic, assign) NSInteger generateCount;
@property (nonatomic, assign) NSInteger settingsCount;
@property (nonatomic, assign) NSInteger saveSpecimenCount;
@property (nonatomic, assign) NSInteger loadSpecimenFileCount;
@property (nonatomic, copy, nullable) NSString *lastPrompt;
@property (nonatomic, assign) NSUInteger lastVariation;
@property (nonatomic, strong, nullable) SpecimenPreset *lastPreset;
@end

@implementation SEMTestDrawerDelegate
- (void)aiDrawerDidRequestGenerate:(NSString *)prompt variation:(NSUInteger)variation {
    self.generateCount += 1;
    self.lastPrompt = prompt;
    self.lastVariation = variation;
}
- (void)aiDrawerDidRequestLoadBuiltInModel:(SpecimenPreset *)preset {
    self.lastPreset = preset;
}
- (void)aiDrawerDidRequestSaveSpecimen:(id)drawer {
    self.saveSpecimenCount += 1;
}
- (void)aiDrawerDidRequestLoadSpecimenFile:(id)drawer {
    self.loadSpecimenFileCount += 1;
}
- (void)aiDrawerDidRequestSettings:(id)drawer {
    self.settingsCount += 1;
}
@end

@interface SEMTestConsoleDelegate : NSObject <ConsoleViewDelegate>
@property (nonatomic, assign) NSInteger aiCount;
@property (nonatomic, assign) NSInteger saveCount;
@property (nonatomic, assign) NSInteger settingsCount;
@property (nonatomic, assign) NSInteger helpCount;
@property (nonatomic, assign) SEMPhosphorMode lastPhosphorMode;
@end

@implementation SEMTestConsoleDelegate
- (void)consoleViewDidRequestAI:(id)consoleView { self.aiCount += 1; }
- (void)consoleViewDidRequestSave:(id)consoleView { self.saveCount += 1; }
- (void)consoleViewDidRequestSettings:(id)consoleView { self.settingsCount += 1; }
- (void)consoleViewDidRequestHelp:(id)consoleView { self.helpCount += 1; }
- (void)consoleView:(id)consoleView didSelectPhosphorMode:(SEMPhosphorMode)mode {
    self.lastPhosphorMode = mode;
}
@end

@interface ConsoleView (SEMTesting)
- (void)detectorChanged:(NSSegmentedControl *)sender;
- (void)scanModeChanged:(NSSegmentedControl *)sender;
- (void)phosphorChanged:(NSSegmentedControl *)sender;
- (void)unitsChanged:(NSSegmentedControl *)sender;
- (void)rockerChanged:(RockerSwitchControl *)sender;
@end

@interface HelpWindowController (SEMTesting)
- (NSAttributedString *)helpContent;
@end

static NSArray<NSView *> *SEMAllSubviews(NSView *root) {
    NSMutableArray<NSView *> *result = [NSMutableArray array];
    for (NSView *subview in root.subviews) {
        [result addObject:subview];
        [result addObjectsFromArray:SEMAllSubviews(subview)];
    }
    return result;
}

static NSButton *SEMFindButtonWithTitle(NSView *root, NSString *title) {
    for (NSView *view in SEMAllSubviews(root)) {
        if ([view isKindOfClass:[NSButton class]] && [((NSButton *)view).title isEqualToString:title]) {
            return (NSButton *)view;
        }
    }
    return nil;
}

static BOOL SEMWaitForCondition(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && [deadline timeIntervalSinceNow] > 0.0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    }
    return condition();
}

static BOOL SEMImageHasVisibleContent(NSImage *image) {
    NSData *tiff = image.TIFFRepresentation;
    if (!tiff) return NO;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
    if (!rep) return NO;

    NSUInteger width = rep.pixelsWide;
    NSUInteger height = rep.pixelsHigh;
    if (width == 0 || height == 0) return NO;

    NSUInteger maxLuminance = 0;
    NSUInteger stepX = MAX((NSUInteger)1, width / 64);
    NSUInteger stepY = MAX((NSUInteger)1, height / 64);
    for (NSUInteger y = 0; y < height; y += stepY) {
        for (NSUInteger x = 0; x < width; x += stepX) {
            NSColor *color = [[rep colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
            if (!color) continue;
            CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
            [color getRed:&red green:&green blue:&blue alpha:&alpha];
            NSUInteger luminance = (NSUInteger)(255.0 * MAX(red, MAX(green, blue)));
            if (luminance > maxLuminance) maxLuminance = luminance;
        }
    }
    return maxLuminance > 12;
}

#pragma mark - Minimal HTTP stub for OpenCode tests

typedef NSDictionary<NSString *, id> * _Nullable (^SEMStubHTTPHandler)(NSString *method,
                                                                      NSString *path,
                                                                      NSDictionary<NSString *, id> * _Nullable body);

@interface SEMStubHTTPServer : NSObject
@property (nonatomic, readonly) uint16_t port;
@property (nonatomic, readonly) NSString *baseURL;
@property (atomic, assign) BOOL running;
- (BOOL)startWithHandler:(SEMStubHTTPHandler)handler error:(NSError **)error;
- (void)stop;
@end

@implementation SEMStubHTTPServer {
    int _listenFD;
    uint16_t _port;
    SEMStubHTTPHandler _handler;
}

- (NSString *)baseURL {
    return [NSString stringWithFormat:@"http://127.0.0.1:%u", _port];
}

static NSError *SEMStubSocketError(NSString *operation) {
    NSString *reason = [NSString stringWithUTF8String:strerror(errno)] ?: @"unknown error";
    return [NSError errorWithDomain:NSPOSIXErrorDomain
                               code:errno
                           userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ failed: %@", operation, reason]}];
}

- (BOOL)startWithHandler:(SEMStubHTTPHandler)handler error:(NSError **)error {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        if (error) *error = SEMStubSocketError(@"socket");
        return NO;
    }

    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    struct sockaddr_in address;
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(0);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);

    if (bind(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        if (error) *error = SEMStubSocketError(@"bind");
        close(fd);
        return NO;
    }
    if (listen(fd, 8) < 0) {
        if (error) *error = SEMStubSocketError(@"listen");
        close(fd);
        return NO;
    }

    socklen_t length = sizeof(address);
    if (getsockname(fd, (struct sockaddr *)&address, &length) < 0) {
        if (error) *error = SEMStubSocketError(@"getsockname");
        close(fd);
        return NO;
    }

    _listenFD = fd;
    _port = ntohs(address.sin_port);
    _handler = [handler copy];
    self.running = YES;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self acceptLoop];
    });
    return YES;
}

- (void)stop {
    self.running = NO;
    int fd = _listenFD;
    _listenFD = -1;
    if (fd >= 0) {
        shutdown(fd, SHUT_RDWR);
        close(fd);
    }
}

- (void)dealloc {
    [self stop];
}

- (void)acceptLoop {
    int listenFD = _listenFD;
    while (self.running && listenFD >= 0) {
        int clientFD = accept(listenFD, NULL, NULL);
        if (clientFD < 0) break;
        int noSigPipe = 1;
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, sizeof(noSigPipe));
        [self handleClient:clientFD];
    }
}

- (void)handleClient:(int)clientFD {
    NSMutableData *requestData = [NSMutableData data];
    NSUInteger headerEnd = NSNotFound;
    NSUInteger contentLength = 0;
    NSData *separator = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding];

    while (self.running) {
        uint8_t buffer[4096];
        ssize_t count = read(clientFD, buffer, sizeof(buffer));
        if (count <= 0) break;
        [requestData appendBytes:buffer length:(NSUInteger)count];

        if (headerEnd == NSNotFound) {
            NSRange range = [requestData rangeOfData:separator
                                             options:0
                                               range:NSMakeRange(0, requestData.length)];
            if (range.location != NSNotFound) {
                headerEnd = range.location + range.length;
                NSString *headers = [[NSString alloc] initWithData:[requestData subdataWithRange:NSMakeRange(0, headerEnd)]
                                                           encoding:NSUTF8StringEncoding];
                for (NSString *line in [headers componentsSeparatedByString:@"\r\n"]) {
                    if ([line.lowercaseString hasPrefix:@"content-length:"]) {
                        contentLength = (NSUInteger)MAX(0, [[line substringFromIndex:15] integerValue]);
                    }
                }
            }
        }

        if (headerEnd != NSNotFound && requestData.length >= headerEnd + contentLength) break;
    }

    if (headerEnd == NSNotFound) {
        close(clientFD);
        return;
    }

    NSString *headers = [[NSString alloc] initWithData:[requestData subdataWithRange:NSMakeRange(0, headerEnd)]
                                               encoding:NSUTF8StringEncoding];
    NSString *requestLine = [[headers componentsSeparatedByString:@"\r\n"] firstObject] ?: @"";
    NSArray<NSString *> *parts = [requestLine componentsSeparatedByString:@" "];
    NSString *method = parts.count > 0 ? parts[0] : @"GET";
    NSString *path = parts.count > 1 ? parts[1] : @"/";
    path = [[path componentsSeparatedByString:@"?"] firstObject] ?: path;

    NSDictionary<NSString *, id> *body = nil;
    if (contentLength > 0 && requestData.length >= headerEnd + contentLength) {
        NSData *bodyData = [requestData subdataWithRange:NSMakeRange(headerEnd, contentLength)];
        id object = [NSJSONSerialization JSONObjectWithData:bodyData options:0 error:NULL];
        if ([object isKindOfClass:[NSDictionary class]]) body = object;
    }

    NSDictionary<NSString *, id> *response = _handler ? _handler(method, path, body) : nil;
    NSInteger status = [response[@"status"] isKindOfClass:[NSNumber class]] ? [response[@"status"] integerValue] : 200;

    NSData *responseBody = nil;
    if ([response[@"raw"] isKindOfClass:[NSData class]]) {
        responseBody = response[@"raw"];
    } else if ([response[@"json"] isKindOfClass:[NSDictionary class]]) {
        responseBody = [NSJSONSerialization dataWithJSONObject:response[@"json"] options:0 error:NULL];
    }
    if (!responseBody) responseBody = [NSData data];

    NSString *reason = @"OK";
    if (status == 401) reason = @"Unauthorized";
    else if (status == 403) reason = @"Forbidden";
    else if (status == 404) reason = @"Not Found";
    else if (status == 429) reason = @"Too Many Requests";
    else if (status == 502) reason = @"Bad Gateway";

    NSString *header = [NSString stringWithFormat:
                        @"HTTP/1.1 %ld %@\r\n"
                        @"Content-Type: application/json\r\n"
                        @"Content-Length: %lu\r\n"
                        @"Connection: close\r\n\r\n",
                        (long)status, reason, (unsigned long)responseBody.length];
    NSMutableData *responseData = [NSMutableData dataWithData:[header dataUsingEncoding:NSUTF8StringEncoding]];
    [responseData appendData:responseBody];

    const uint8_t *bytes = responseData.bytes;
    NSUInteger remaining = responseData.length;
    while (remaining > 0) {
        ssize_t written = write(clientFD, bytes, remaining);
        if (written <= 0) break;
        bytes += written;
        remaining -= (NSUInteger)written;
    }
    close(clientFD);
}

@end

#pragma mark - UI tests

@interface SEMUITests : XCTestCase
@end

@implementation SEMUITests

- (void)testThemePanelLEDAndRockerSwitch {
    XCTAssertNotNil([Theme consoleBackground]);
    XCTAssertNotNil([Theme panelFace]);
    XCTAssertNotNil([Theme accentGreen]);
    XCTAssertGreaterThan([Theme labelFont].pointSize, 0.0);
    XCTAssertGreaterThan([Theme titleFont].pointSize, 0.0);
    XCTAssertGreaterThan([Theme monoFontOfSize:10].pointSize, 0.0);

    PanelView *panel = [[PanelView alloc] initWithFrame:NSMakeRect(0, 0, 240, 120)];
    panel.title = @"VACUUM SYSTEM";
    XCTAssertEqualObjects(panel.title, @"VACUUM SYSTEM");

    LEDIndicatorView *led = [[LEDIndicatorView alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    led.color = [NSColor redColor];
    led.on = YES;
    XCTAssertTrue(led.isOn);
    XCTAssertEqualObjects(led.color, [NSColor redColor]);

    RockerSwitchControl *rocker = [[RockerSwitchControl alloc] initWithTitle:@"HV"];
    SEMTestActionTarget *target = [[SEMTestActionTarget alloc] init];
    rocker.target = target;
    rocker.action = @selector(actionFired:);

    NSEvent *space = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                     location:NSZeroPoint
                                modifierFlags:0
                                    timestamp:0
                                 windowNumber:0
                                      context:nil
                                   characters:@" "
                  charactersIgnoringModifiers:@" "
                                    isARepeat:NO
                                      keyCode:49];
    [rocker keyDown:space];
    XCTAssertTrue(rocker.isOn);
    XCTAssertEqual(target.actionCount, 1);
    [rocker keyDown:space];
    XCTAssertFalse(rocker.isOn);
    XCTAssertEqual(target.actionCount, 2);
}

- (void)testRotaryVoltageAndPressureControls {
    RotaryKnobControl *knob = [[RotaryKnobControl alloc] initWithLabel:@"MAGNIFICATION"
                                                                   min:10.0
                                                                   max:100000.0
                                                          defaultValue:1000.0
                                                                  unit:@"x"];
    knob.logarithmic = YES;
    knob.doubleValue = 1.0;
    XCTAssertEqualWithAccuracy(knob.doubleValue, 10.0, 0.001);
    knob.doubleValue = 1.0e9;
    XCTAssertEqualWithAccuracy(knob.doubleValue, 100000.0, 0.001);
    knob.doubleValue = 1000.0;
    XCTAssertEqualWithAccuracy(knob.normalizedValue, 0.5, 0.01);
    knob.valueFormatter = ^NSString *(double value) {
        return [NSString stringWithFormat:@"%.0fx", value];
    };
    XCTAssertEqualObjects(knob.valueFormatter(2500.0), @"2500x");
    knob.defaultValue = 5000.0;
    XCTAssertEqualWithAccuracy(knob.defaultValue, 5000.0, 0.001);
    [knob setDoubleValueSilently:250.0];
    XCTAssertEqualWithAccuracy(knob.doubleValue, 250.0, 0.001);

    VoltageSelectorView *voltage = [[VoltageSelectorView alloc] initWithFrame:NSMakeRect(0, 0, 300, 38)];
    XCTAssertEqual(voltage.selectedKV, 15);
    voltage.selectedKV = 12;
    XCTAssertEqual(voltage.selectedKV, 10);
    voltage.selectedKV = 13;
    XCTAssertEqual(voltage.selectedKV, 15);
    voltage.selectedKV = 100;
    XCTAssertEqual(voltage.selectedKV, 25);

    SEMTestActionTarget *target = [[SEMTestActionTarget alloc] init];
    voltage.target = target;
    voltage.action = @selector(actionFired:);
    voltage.selectedKV = 10;
    NSEvent *right = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                    characters:@""
                   charactersIgnoringModifiers:@""
                                     isARepeat:NO
                                       keyCode:124];
    [voltage keyDown:right];
    XCTAssertEqual(voltage.selectedKV, 15);
    XCTAssertEqual(target.actionCount, 1);

    PressureGaugeView *gauge = [[PressureGaugeView alloc] initWithFrame:NSMakeRect(0, 0, 174, 118)];
    gauge.pressurePa = -1.0;
    XCTAssertEqualWithAccuracy(gauge.pressurePa, 1.0e-6, 1.0e-12);
    gauge.pressurePa = 1.0e-4;
    XCTAssertEqualWithAccuracy(gauge.pressurePa, 1.0e-4, 1.0e-12);
    gauge.torr = YES;
    XCTAssertTrue(gauge.isTorr);
}

- (void)testAISampleDrawerPromptStyleAndBusyState {
    AISampleDrawer *drawer = [[AISampleDrawer alloc] initWithFrame:NSMakeRect(0, 0, 900, 260)];
    [drawer setFrameSize:NSMakeSize(900, 260)];
    [drawer layoutSubtreeIfNeeded];

    NSTextField *prompt = [drawer valueForKey:@"promptField"];
    XCTAssertTrue([prompt isKindOfClass:[NSTextField class]]);
    XCTAssertEqualObjects(prompt.textColor, [NSColor blackColor]);
    XCTAssertEqualObjects(prompt.backgroundColor, [NSColor whiteColor]);
    XCTAssertTrue(prompt.drawsBackground);
    XCTAssertTrue(prompt.isBezeled);
    XCTAssertTrue([prompt.placeholderAttributedString.string containsString:@"Describe a specimen"]);

    for (NSString *title in @[@"SET", @"GENERATE + LOAD", @"VARIATION", @"LOAD OFFLINE",
                              @"SAVE SPECIMEN", @"LOAD FILE…"]) {
        NSButton *button = SEMFindButtonWithTitle(drawer, title);
        XCTAssertNotNil(button, @"Missing %@ button", title);
        NSAttributedString *attributedTitle = button.attributedTitle;
        XCTAssertGreaterThan(attributedTitle.length, 0);
        NSColor *color = [attributedTitle attribute:NSForegroundColorAttributeName
                                           atIndex:0
                                    effectiveRange:NULL];
        XCTAssertEqualObjects(color, [NSColor blackColor], @"%@ button title is not black", title);
    }

    XCTAssertFalse(SEMFindButtonWithTitle(drawer, @"SAVE SPECIMEN").enabled,
                   @"Save must be disabled until a specimen exists");
    XCTAssertTrue(SEMFindButtonWithTitle(drawer, @"LOAD FILE…").enabled);

    drawer.busy = YES;
    XCTAssertFalse(prompt.enabled);
    XCTAssertFalse(SEMFindButtonWithTitle(drawer, @"GENERATE + LOAD").enabled);
    XCTAssertFalse(SEMFindButtonWithTitle(drawer, @"VARIATION").enabled);
    XCTAssertFalse(SEMFindButtonWithTitle(drawer, @"LOAD OFFLINE").enabled);
    XCTAssertFalse(SEMFindButtonWithTitle(drawer, @"SAVE SPECIMEN").enabled);
    XCTAssertFalse(SEMFindButtonWithTitle(drawer, @"LOAD FILE…").enabled);
    drawer.busy = NO;
    XCTAssertTrue(prompt.enabled);
    XCTAssertTrue(SEMFindButtonWithTitle(drawer, @"GENERATE + LOAD").enabled);
    XCTAssertTrue(SEMFindButtonWithTitle(drawer, @"LOAD FILE…").enabled);

    SEMSpecimen *specimen = [[SEMSpecimen alloc] init];
    specimen.name = @"Saveable";
    specimen.templateName = @"crystal";
    [drawer setSpecimen:specimen];
    XCTAssertTrue(SEMFindButtonWithTitle(drawer, @"SAVE SPECIMEN").enabled);
}

- (void)testAISampleDrawerDelegateCallbacks {
    AISampleDrawer *drawer = [[AISampleDrawer alloc] initWithFrame:NSMakeRect(0, 0, 900, 260)];
    SEMTestDrawerDelegate *delegate = [[SEMTestDrawerDelegate alloc] init];
    drawer.delegate = delegate;

    NSTextField *prompt = [drawer valueForKey:@"promptField"];
    prompt.stringValue = @"salt crystals";

    NSButton *generate = SEMFindButtonWithTitle(drawer, @"GENERATE + LOAD");
    [generate performClick:nil];
    XCTAssertEqual(delegate.generateCount, 1);
    XCTAssertEqualObjects(delegate.lastPrompt, @"salt crystals");
    XCTAssertGreaterThanOrEqual(delegate.lastVariation, 0);

    NSButton *variation = SEMFindButtonWithTitle(drawer, @"VARIATION");
    [variation performClick:nil];
    XCTAssertEqual(delegate.generateCount, 2);

    NSPopUpButton *popup = [drawer valueForKey:@"builtInPopup"];
    NSMutableArray<SpecimenPreset *> *popupModels = [NSMutableArray array];
    for (NSMenuItem *item in popup.itemArray) {
        if ([item.representedObject isKindOfClass:[SpecimenPreset class]]) {
            [popupModels addObject:item.representedObject];
        }
    }
    XCTAssertEqual(popupModels.count, [SpecimenLibrary offlineModels].count);
    [popup selectItemAtIndex:2];
    NSButton *load = SEMFindButtonWithTitle(drawer, @"LOAD OFFLINE");
    [load performClick:nil];
    XCTAssertNotNil(delegate.lastPreset);

    SEMSpecimen *specimen = [[SEMSpecimen alloc] init];
    specimen.name = @"Saveable";
    specimen.templateName = @"crystal";
    [drawer setSpecimen:specimen];
    [SEMFindButtonWithTitle(drawer, @"SAVE SPECIMEN") performClick:nil];
    XCTAssertEqual(delegate.saveSpecimenCount, 1);

    [SEMFindButtonWithTitle(drawer, @"LOAD FILE…") performClick:nil];
    XCTAssertEqual(delegate.loadSpecimenFileCount, 1);

    NSButton *settings = SEMFindButtonWithTitle(drawer, @"SET");
    [settings performClick:nil];
    XCTAssertEqual(delegate.settingsCount, 1);
}

- (void)testAISampleDrawerSpecimenSummary {
    AISampleDrawer *drawer = [[AISampleDrawer alloc] initWithFrame:NSMakeRect(0, 0, 900, 260)];
    SEMSpecimen *specimen = [[SEMSpecimen alloc] init];
    specimen.name = @"Test salt";
    specimen.templateName = @"crystal";
    specimen.meanZ = 18.0;
    specimen.conductive = NO;
    specimen.coatingRecommended = YES;

    [drawer setSpecimen:specimen];
    NSTextField *summary = [drawer valueForKey:@"summaryLabel"];
    XCTAssertTrue([summary.stringValue containsString:@"TEST SALT"]);
    XCTAssertTrue([summary.stringValue containsString:@"CRYSTAL"]);
    XCTAssertTrue([summary.stringValue containsString:@"CONDUCTIVE: NO"]);
    XCTAssertTrue([summary.stringValue containsString:@"COATING: RECOMMENDED"]);

    [drawer setSpecimen:nil];
    XCTAssertTrue([summary.stringValue containsString:@"No specimen yet"]);
}

- (void)testConsoleViewControlsAndRefresh {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    ConsoleView *console = [[ConsoleView alloc] initWithEngine:engine];
    [console setFrameSize:NSMakeSize(600, 900)];
    [console layoutSubtreeIfNeeded];
    [console refreshFromEngine];

    PressureGaugeView *gauge = [console valueForKey:@"gauge"];
    RotaryKnobControl *magnification = [console valueForKey:@"magnificationKnob"];
    VoltageSelectorView *voltage = [console valueForKey:@"voltageSelector"];
    RockerSwitchControl *hv = [console valueForKey:@"hvSwitch"];
    NSTextField *status = [console valueForKey:@"statusLabel"];
    XCTAssertNotNil(gauge);
    XCTAssertNotNil(magnification);
    XCTAssertNotNil(voltage);
    XCTAssertNotNil(hv);
    XCTAssertNotNil(status);

    XCTAssertEqualWithAccuracy(gauge.pressurePa, engine.pressurePa, 1.0e-9);
    XCTAssertEqualWithAccuracy(magnification.doubleValue, engine.magnification, 0.001);
    XCTAssertEqual(voltage.selectedKV, engine.acceleratingVoltageKV);
    XCTAssertEqual(hv.isOn, engine.highVoltageOn);
    XCTAssertEqualObjects(status.stringValue, engine.statusMessage);

    [engine setMagnification:5000.0];
    [engine setAcceleratingVoltageKV:20];
    [console refreshFromEngine];
    XCTAssertEqualWithAccuracy(magnification.doubleValue, 5000.0, 0.001);
    XCTAssertEqual(voltage.selectedKV, 20);

    NSUInteger knobs = 0, rockers = 0, selectors = 0, gauges = 0;
    for (NSView *view in SEMAllSubviews(console)) {
        if ([view isKindOfClass:[RotaryKnobControl class]]) knobs++;
        else if ([view isKindOfClass:[RockerSwitchControl class]]) rockers++;
        else if ([view isKindOfClass:[VoltageSelectorView class]]) selectors++;
        else if ([view isKindOfClass:[PressureGaugeView class]]) gauges++;
    }
    XCTAssertGreaterThanOrEqual(knobs, 16);
    XCTAssertGreaterThanOrEqual(rockers, 4);
    XCTAssertEqual(selectors, 1);
    XCTAssertEqual(gauges, 1);

    NSSegmentedControl *detector = [console valueForKey:@"detectorControl"];
    detector.selectedSegment = 1;
    [console detectorChanged:detector];
    XCTAssertEqual(engine.detectorMode, SEMDetectorModeBSE);

    NSSegmentedControl *scan = [console valueForKey:@"scanControl"];
    scan.selectedSegment = 1;
    [console scanModeChanged:scan];
    XCTAssertEqual(engine.scanMode, SEMScanModeSlow);

    NSSegmentedControl *phosphor = [console valueForKey:@"phosphorControl"];
    phosphor.selectedSegment = 1;
    [console phosphorChanged:phosphor];
    XCTAssertEqual(console.phosphorMode, SEMPhosphorModeAmber);

    NSSegmentedControl *units = [console valueForKey:@"unitsControl"];
    units.selectedSegment = 1;
    [console unitsChanged:units];
    XCTAssertTrue(gauge.isTorr);

    RockerSwitchControl *rp = [console valueForKey:@"rpSwitch"];
    rp.on = YES;
    [console rockerChanged:rp];
    XCTAssertTrue(engine.roughingPumpOn);

    NSButton *evac = SEMFindButtonWithTitle(console, @"EVAC");
    XCTAssertNotNil(evac);
    [evac performClick:nil];
    XCTAssertTrue(engine.roughingPumpOn);

    NSButton *vent = SEMFindButtonWithTitle(console, @"VENT");
    XCTAssertNotNil(vent);
    [vent performClick:nil];
    XCTAssertEqual(engine.vacuumState, SEMVacuumStateVenting);
}

- (void)testConsoleViewDelegateCallbacks {
    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    ConsoleView *console = [[ConsoleView alloc] initWithEngine:engine];
    SEMTestConsoleDelegate *delegate = [[SEMTestConsoleDelegate alloc] init];
    console.delegate = delegate;

    [SEMFindButtonWithTitle(console, @"SAVE") performClick:nil];
    [SEMFindButtonWithTitle(console, @"HELP") performClick:nil];
    [SEMFindButtonWithTitle(console, @"SET") performClick:nil];
    [SEMFindButtonWithTitle(console, @"SPECIMEN…") performClick:nil];
    XCTAssertEqual(delegate.saveCount, 1);
    XCTAssertEqual(delegate.helpCount, 1);
    XCTAssertEqual(delegate.settingsCount, 1);
    XCTAssertEqual(delegate.aiCount, 1);

    NSSegmentedControl *phosphor = [console valueForKey:@"phosphorControl"];
    phosphor.selectedSegment = 2;
    [console phosphorChanged:phosphor];
    XCTAssertEqual(delegate.lastPhosphorMode, SEMPhosphorModeWhite);
    XCTAssertEqual(console.phosphorMode, SEMPhosphorModeWhite);
}

- (void)testSettingsWindowExposesOpenCodeAndOfflineControls {
    SettingsWindowController *settings = [[SettingsWindowController alloc] init];
    NSTextField *urlField = [settings valueForKey:@"openCodeURLField"];
    NSPopUpButton *modelPopup = [settings valueForKey:@"openCodeModelPopup"];
    NSSecureTextField *keyField = [settings valueForKey:@"openCodeKeyField"];
    NSTextField *openCodeStatus = [settings valueForKey:@"openCodeStatusLabel"];
    NSButton *testButton = [settings valueForKey:@"openCodeTestButton"];
    NSButton *refreshButton = [settings valueForKey:@"openCodeRefreshButton"];
    NSTextField *maintenanceStatus = [settings valueForKey:@"maintenanceStatusLabel"];
    NSPopUpButton *builtInPopup = [settings valueForKey:@"builtInModelPopup"];
    NSTextField *builtInDetail = [settings valueForKey:@"builtInDetailLabel"];
    NSTextField *builtInStatus = [settings valueForKey:@"builtInStatusLabel"];

    XCTAssertTrue([urlField isKindOfClass:[NSTextField class]]);
    XCTAssertTrue([modelPopup isKindOfClass:[NSPopUpButton class]]);
    XCTAssertTrue([keyField isKindOfClass:[NSSecureTextField class]]);
    XCTAssertTrue([openCodeStatus isKindOfClass:[NSTextField class]]);
    XCTAssertTrue([testButton isKindOfClass:[NSButton class]]);
    XCTAssertTrue([refreshButton isKindOfClass:[NSButton class]]);
    XCTAssertTrue([maintenanceStatus isKindOfClass:[NSTextField class]]);
    XCTAssertTrue([builtInPopup isKindOfClass:[NSPopUpButton class]]);
    XCTAssertTrue([builtInDetail isKindOfClass:[NSTextField class]]);
    XCTAssertTrue([builtInStatus isKindOfClass:[NSTextField class]]);

    NSUInteger popupModelCount = 0;
    for (NSMenuItem *item in builtInPopup.itemArray) {
        if ([item.representedObject isKindOfClass:[SpecimenPreset class]]) popupModelCount++;
    }
    XCTAssertEqual(popupModelCount, [SpecimenLibrary offlineModels].count);
    NSView *root = settings.window.contentView;
    XCTAssertNotNil(SEMFindButtonWithTitle(root, @"SAVE OPENCODE"));
    XCTAssertNotNil(SEMFindButtonWithTitle(root, @"LOAD PASSWORD FILE…"));
    XCTAssertNotNil(SEMFindButtonWithTitle(root, @"REPLACE FILAMENT"));
    XCTAssertNotNil(SEMFindButtonWithTitle(root, @"RESET VACUUM FAULT"));
    XCTAssertNotNil(SEMFindButtonWithTitle(root, @"CLEAR CONTAMINATION"));
    XCTAssertNotNil(SEMFindButtonWithTitle(root, @"LOAD OFFLINE"));
    [settings.window close];
}

- (void)testHelpWindowContentCoversCoreSections {
    HelpWindowController *help = [[HelpWindowController alloc] init];
    NSAttributedString *content = [help helpContent];
    NSString *text = content.string;
    XCTAssertGreaterThan(text.length, 1000);
    for (NSString *section in @[@"QUICK START",
                                @"MOUSE, TRACKPAD, AND KEYBOARD",
                                @"VACUUM SYSTEM",
                                @"SPECIMEN GENERATOR",
                                @"OFFLINE MODELS (BUILT-IN + SAVED)",
                                @"OPENCODE"]) {
        XCTAssertTrue([text containsString:section], @"Help is missing section %@", section);
    }
    XCTAssertTrue([text containsString:@"SAVE SPECIMEN"]);
    XCTAssertTrue([text containsString:@".semspecimen"]);
    [help.window close];
}

- (void)testMainWindowBuildsConsoleCRTAndDrawer {
    MainWindowController *controller = [[MainWindowController alloc] init];
    XCTAssertNotNil(controller.engine);
    XCTAssertNotNil(controller.window);

    ConsoleView *console = [controller valueForKey:@"consoleView"];
    MetalCRTView *crt = [controller valueForKey:@"crtView"];
    AISampleDrawer *drawer = [controller valueForKey:@"aiDrawer"];
    XCTAssertTrue([console isKindOfClass:[ConsoleView class]]);
    XCTAssertTrue([crt isKindOfClass:[MetalCRTView class]]);
    XCTAssertTrue([drawer isKindOfClass:[AISampleDrawer class]]);
    XCTAssertEqual(console.engine, controller.engine);
    XCTAssertEqual(crt.engine, controller.engine);
    XCTAssertEqual((id)console.delegate, controller);
    XCTAssertEqual((id)drawer.delegate, controller);
    XCTAssertEqualObjects(controller.window.title, @"SEM Simulator");
    XCTAssertGreaterThan(controller.window.contentView.subviews.count, 0);

    NSTimer *timer = [controller valueForKey:@"timer"];
    [timer invalidate];
    [controller.window close];
}

- (void)testMainWindowZoomActions {
    MainWindowController *controller = [[MainWindowController alloc] init];
    MetalCRTView *crt = [controller valueForKey:@"crtView"];
    double initial = controller.engine.magnification;

    [controller zoomIn:controller];
    for (NSInteger index = 0; index < 120; index++) {
        [crt drawFrame];
    }
    XCTAssertGreaterThan(controller.engine.magnification, initial);

    [controller resetZoom:controller];
    XCTAssertEqualWithAccuracy(controller.engine.magnification, 1000.0, 0.001);

    [controller zoomOut:controller];
    for (NSInteger index = 0; index < 120; index++) {
        [crt drawFrame];
    }
    XCTAssertLessThan(controller.engine.magnification, 1000.0);

    NSTimer *timer = [controller valueForKey:@"timer"];
    [timer invalidate];
    [controller.window close];
}

- (void)testMainWindowOfflineModelLoadRunsAutoEvacAndHV {
    MainWindowController *controller = [[MainWindowController alloc] init];
    AISampleDrawer *drawer = [controller valueForKey:@"aiDrawer"];
    BOOL idle = SEMWaitForCondition(^BOOL {
        return !drawer.isBusy;
    }, 20.0);
    XCTAssertTrue(idle, @"Default specimen generation did not finish");

    SpecimenPreset *preset = [SpecimenLibrary builtInModels][1];
    [controller loadOfflineSpecimen:preset];

    BOOL loaded = SEMWaitForCondition(^BOOL {
        return [controller.engine.specimen.name isEqualToString:preset.name];
    }, 20.0);
    XCTAssertTrue(loaded, @"Offline model was not loaded into the chamber");
    XCTAssertTrue(controller.engine.roughingPumpOn || controller.engine.diffusionPumpOn ||
                  controller.engine.vacuumState == SEMVacuumStateHighVacuum,
                  @"Offline load did not start evacuation");

    SEMAdvance(controller.engine, 45.0);
    XCTAssertTrue(controller.engine.vacuumReady);
    XCTAssertTrue(controller.engine.highVoltageOn);
    XCTAssertTrue(controller.engine.beamOn);

    NSTimer *timer = [controller valueForKey:@"timer"];
    [timer invalidate];
    [controller.window close];
}

- (void)testMetalCRTViewRendersGeneratedSpecimen {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        XCTSkip(@"Metal is unavailable on this machine.");
    }

    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    SpecimenPreset *preset = [SpecimenLibrary builtInModels].firstObject;
    XCTestExpectation *expectation = [self expectationWithDescription:@"built-in specimen for CRT"];
    __block SEMSpecimen *generated = nil;
    [manager generateSpecimenForPreset:preset completion:^(SEMSpecimen *specimen, NSError *error) {
        generated = specimen;
        XCTAssertNotNil(specimen, @"Generation failed: %@", error);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];
    XCTAssertNotNil(generated);

    SEMPhysicsEngine *engine = [[SEMPhysicsEngine alloc] init];
    engine.specimen = generated;
    [engine evac];
    SEMAdvance(engine, 45.0);
    XCTAssertTrue(engine.beamOn);

    MetalCRTView *view = [[MetalCRTView alloc] initWithFrame:NSMakeRect(0, 0, 320, 240)
                                                      device:device
                                                      engine:engine];
    view.specimen = generated;
    [view drawFrame];
    NSImage *frame = view.currentFrameImage;
    XCTAssertNotNil(frame);
    XCTAssertTrue(SEMImageHasVisibleContent(frame));
}

- (void)testOpenCodePromptLoadsSpecimenAndRendersCRT {
    NSString *recipe = @"{\"name\":\"Stub salt crystals\",\"template\":\"crystal\",\"features\":{\"spikes\":0.1,\"pores\":0.2,\"roughness\":0.5,\"cracks\":0.2,\"fibers\":0,\"grain\":0.4},\"material\":{\"meanZ\":18,\"conductive\":false,\"coatingRecommended\":true},\"scaleUm\":80}";

    SEMStubHTTPServer *server = [[SEMStubHTTPServer alloc] init];
    NSError *serverError = nil;
    BOOL started = [server startWithHandler:^NSDictionary<NSString *, id> *(NSString *method, NSString *path, NSDictionary<NSString *, id> *body) {
        if ([path isEqualToString:@"/api/model"]) {
            return @{@"status": @200,
                     @"json": @{@"data": @[
                         @{@"providerID": @"opencode", @"id": @"stub-free", @"name": @"Stub Free",
                           @"type": @"chat", @"enabled": @YES}
                     ]}};
        }
        if ([path isEqualToString:@"/api/experimental/generate/text"]) {
            return @{@"status": @200, @"json": @{@"data": @{@"text": recipe}}};
        }
        return @{@"status": @404, @"json": @{@"message": @"not found"}};
    } error:&serverError];
    XCTAssertTrue(started, @"Could not start stub server: %@", serverError);

    NSString *oldURL = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    NSString *oldModel = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeModelDefaultsKey];
    [OpenCodeIntegration setServerURL:server.baseURL];
    [OpenCodeIntegration setConfiguredModel:@"opencode/stub-free"];

    MainWindowController *controller = [[MainWindowController alloc] init];
    BOOL defaultReady = SEMWaitForCondition(^BOOL {
        return controller.engine.specimen != nil;
    }, 15.0);
    XCTAssertTrue(defaultReady, @"Default specimen did not load");

    AISampleDrawer *drawer = [controller valueForKey:@"aiDrawer"];
    NSTextField *prompt = [drawer valueForKey:@"promptField"];
    prompt.stringValue = @"salt crystals";
    NSButton *generate = SEMFindButtonWithTitle(drawer, @"GENERATE + LOAD");
    XCTAssertNotNil(generate);
    [generate performClick:nil];

    BOOL loaded = SEMWaitForCondition(^BOOL {
        return [controller.engine.specimen.name isEqualToString:@"Stub salt crystals"];
    }, 20.0);
    XCTAssertTrue(loaded, @"OpenCode stub specimen was not loaded into the chamber");
    MetalCRTView *crt = [controller valueForKey:@"crtView"];
    XCTAssertTrue([crt isKindOfClass:[MetalCRTView class]]);
    XCTAssertEqualObjects(crt.specimen.name, @"Stub salt crystals");

    SEMAdvance(controller.engine, 45.0);
    XCTAssertTrue(controller.engine.vacuumReady);
    XCTAssertTrue(controller.engine.beamOn);

    [controller.window layoutIfNeeded];
    [crt setFrameSize:NSMakeSize(800, 600)];
    [crt drawFrame];
    NSImage *frame = crt.currentFrameImage;
    XCTAssertNotNil(frame);
    XCTAssertTrue(SEMImageHasVisibleContent(frame), @"CRT frame is blank after loading the specimen");

    NSTimer *timer = [controller valueForKey:@"timer"];
    [timer invalidate];
    [controller.window close];
    [server stop];

    if (oldURL.length > 0) {
        [OpenCodeIntegration setServerURL:oldURL];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEMOpenCodeURLDefaultsKey];
    }
    if (oldModel.length > 0) {
        [OpenCodeIntegration setConfiguredModel:oldModel];
    } else {
        [OpenCodeIntegration setConfiguredModel:nil];
    }
}

@end

#pragma mark - OpenCode stub integration tests

@interface SEMOpenCodeStubTests : XCTestCase
@end

@implementation SEMOpenCodeStubTests

- (void)testModelListingAndGenerateTextAgainstStub {
    SEMStubHTTPServer *server = [[SEMStubHTTPServer alloc] init];
    NSError *serverError = nil;
    BOOL started = [server startWithHandler:^NSDictionary<NSString *, id> *(NSString *method, NSString *path, NSDictionary<NSString *, id> *body) {
        if ([path isEqualToString:@"/api/model"]) {
            return @{@"status": @200,
                     @"json": @{@"data": @[
                         @{@"providerID": @"opencode", @"id": @"stub-free", @"name": @"Stub Free",
                           @"type": @"chat", @"enabled": @YES},
                         @{@"providerID": @"ollama", @"id": @"llama3.2:3b", @"name": @"Llama",
                           @"type": @"chat", @"enabled": @YES}
                     ]}};
        }
        if ([path isEqualToString:@"/api/experimental/generate/text"]) {
            return @{@"status": @200, @"json": @{@"data": @{@"text": @"hello from stub"}}};
        }
        return @{@"status": @404, @"json": @{@"message": @"not found"}};
    } error:&serverError];
    XCTAssertTrue(started, @"Could not start stub server: %@", serverError);

    XCTestExpectation *listing = [self expectationWithDescription:@"stub model listing"];
    [OpenCodeIntegration fetchAvailableModelsForURL:server.baseURL password:@"secret"
                                         completion:^(NSArray<NSDictionary<NSString *, id> *> *models, NSError *error) {
        XCTAssertNotNil(models, @"Model listing failed: %@", error);
        XCTAssertEqual(models.count, 2);
        XCTAssertEqualObjects(models.firstObject[@"identifier"], @"ollama/llama3.2:3b");
        [listing fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    NSString *oldURL = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    [OpenCodeIntegration setServerURL:server.baseURL];

    XCTestExpectation *generation = [self expectationWithDescription:@"stub text generation"];
    [OpenCodeIntegration generateTextWithPrompt:@"test" model:@"opencode/stub-free"
                                     completion:^(NSString *text, NSInteger status, NSError *error) {
        XCTAssertEqual(status, 200);
        XCTAssertNil(error);
        XCTAssertEqualObjects(text, @"hello from stub");
        [generation fulfill];
    }];
    [self waitForExpectationsWithTimeout:10 handler:nil];

    [server stop];
    if (oldURL.length > 0) {
        [OpenCodeIntegration setServerURL:oldURL];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEMOpenCodeURLDefaultsKey];
    }
}

- (void)testRateLimitFallsBackToLocalRecipe {
    SEMStubHTTPServer *server = [[SEMStubHTTPServer alloc] init];
    NSError *serverError = nil;
    BOOL started = [server startWithHandler:^NSDictionary<NSString *, id> *(NSString *method, NSString *path, NSDictionary<NSString *, id> *body) {
        return @{@"status": @429, @"json": @{@"message": @"rate limited"}};
    } error:&serverError];
    XCTAssertTrue(started, @"Could not start stub server: %@", serverError);

    NSString *oldURL = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    NSString *oldModel = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeModelDefaultsKey];
    [OpenCodeIntegration setServerURL:server.baseURL];
    [OpenCodeIntegration setConfiguredModel:@"opencode/stub-free"];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTAssertNotNil(device);
    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    XCTestExpectation *expectation = [self expectationWithDescription:@"rate-limit fallback"];
    [manager generateSpecimenUsingOpenCodeForPrompt:@"salt crystals" variation:11
                                         completion:^(SEMSpecimen *specimen, NSError *error) {
        XCTAssertNotNil(specimen, @"Fallback failed: %@", error);
        XCTAssertNil(error);
        XCTAssertTrue([manager.lastGenerationNote containsString:@"RATE LIMITED"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];

    [server stop];
    if (oldURL.length > 0) {
        [OpenCodeIntegration setServerURL:oldURL];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEMOpenCodeURLDefaultsKey];
    }
    if (oldModel.length > 0) {
        [OpenCodeIntegration setConfiguredModel:oldModel];
    } else {
        [OpenCodeIntegration setConfiguredModel:nil];
    }
}

- (void)testAuthFailureFallsBackToLocalRecipe {
    SEMStubHTTPServer *server = [[SEMStubHTTPServer alloc] init];
    NSError *serverError = nil;
    BOOL started = [server startWithHandler:^NSDictionary<NSString *, id> *(NSString *method, NSString *path, NSDictionary<NSString *, id> *body) {
        return @{@"status": @401, @"json": @{@"message": @"authentication required"}};
    } error:&serverError];
    XCTAssertTrue(started, @"Could not start stub server: %@", serverError);

    NSString *oldURL = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    NSString *oldModel = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeModelDefaultsKey];
    [OpenCodeIntegration setServerURL:server.baseURL];
    [OpenCodeIntegration setConfiguredModel:@"opencode/stub-free"];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTAssertNotNil(device);
    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    XCTestExpectation *expectation = [self expectationWithDescription:@"auth fallback"];
    [manager generateSpecimenUsingOpenCodeForPrompt:@"salt crystals" variation:12
                                         completion:^(SEMSpecimen *specimen, NSError *error) {
        XCTAssertNotNil(specimen, @"Fallback failed: %@", error);
        XCTAssertNil(error);
        XCTAssertTrue([manager.lastGenerationNote containsString:@"AUTH FAILED"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];

    [server stop];
    if (oldURL.length > 0) {
        [OpenCodeIntegration setServerURL:oldURL];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEMOpenCodeURLDefaultsKey];
    }
    if (oldModel.length > 0) {
        [OpenCodeIntegration setConfiguredModel:oldModel];
    } else {
        [OpenCodeIntegration setConfiguredModel:nil];
    }
}

- (void)testInvalidRecipeFallsBackToLocalRecipe {
    SEMStubHTTPServer *server = [[SEMStubHTTPServer alloc] init];
    NSError *serverError = nil;
    BOOL started = [server startWithHandler:^NSDictionary<NSString *, id> *(NSString *method, NSString *path, NSDictionary<NSString *, id> *body) {
        return @{@"status": @200, @"json": @{@"data": @{@"text": @"I cannot generate that specimen."}}};
    } error:&serverError];
    XCTAssertTrue(started, @"Could not start stub server: %@", serverError);

    NSString *oldURL = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeURLDefaultsKey];
    NSString *oldModel = [[NSUserDefaults standardUserDefaults] stringForKey:SEMOpenCodeModelDefaultsKey];
    [OpenCodeIntegration setServerURL:server.baseURL];
    [OpenCodeIntegration setConfiguredModel:@"opencode/stub-free"];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    XCTAssertNotNil(device);
    AISampleManager *manager = [[AISampleManager alloc] initWithDevice:device];
    XCTestExpectation *expectation = [self expectationWithDescription:@"invalid-recipe fallback"];
    [manager generateSpecimenUsingOpenCodeForPrompt:@"salt crystals" variation:13
                                         completion:^(SEMSpecimen *specimen, NSError *error) {
        XCTAssertNotNil(specimen, @"Fallback failed: %@", error);
        XCTAssertNil(error);
        XCTAssertTrue([manager.lastGenerationNote containsString:@"INVALID RECIPE"]);
        [expectation fulfill];
    }];
    [self waitForExpectationsWithTimeout:30 handler:nil];

    [server stop];
    if (oldURL.length > 0) {
        [OpenCodeIntegration setServerURL:oldURL];
    } else {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:SEMOpenCodeURLDefaultsKey];
    }
    if (oldModel.length > 0) {
        [OpenCodeIntegration setConfiguredModel:oldModel];
    } else {
        [OpenCodeIntegration setConfiguredModel:nil];
    }
}

@end

#pragma mark - Saved specimen tests

@interface SEMSavedSpecimenTests : XCTestCase
@end

@implementation SEMSavedSpecimenTests

#pragma mark - Saved specimens

- (NSURL *)temporarySpecimenDirectory {
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
                  URLByAppendingPathComponent:[@"SEMSavedSpecimenTests-"
                                              stringByAppendingString:NSUUID.UUID.UUIDString]
                  isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:url
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:NULL];
    return url;
}

- (SEMSpecimen *)specimenForSavedFileTests {
    SEMSpecimen *specimen = [[SEMSpecimen alloc] init];
    specimen.name = @"Saved Crystal";
    specimen.templateName = @"crystal";
    specimen.recipe = [[SemanticPromptParser recipeForPrompt:@"salt crystals" variation:42] dictionaryRepresentation];
    specimen.seed = 42;
    specimen.scaleMicrometers = 35;
    specimen.meanZ = 22;
    specimen.conductive = YES;
    specimen.coatingRecommended = NO;
    specimen.sourcePrompt = @"salt crystals";

    const NSInteger width = 32;
    const NSInteger height = 32;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                   pixelsWide:width
                                                                   pixelsHigh:height
                                                                bitsPerSample:8
                                                              samplesPerPixel:4
                                                                     hasAlpha:YES
                                                                     isPlanar:NO
                                                               colorSpaceName:NSCalibratedRGBColorSpace
                                                                  bytesPerRow:0
                                                                 bitsPerPixel:0];
    NSColor *green = [NSColor colorWithCalibratedRed:0.35 green:0.7 blue:0.4 alpha:1.0];
    for (NSInteger y = 0; y < height; y++) {
        for (NSInteger x = 0; x < width; x++) {
            [rep setColor:green atX:x y:y];
        }
    }
    NSImage *thumbnail = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [thumbnail addRepresentation:rep];
    specimen.thumbnail = thumbnail;
    return specimen;
}

- (void)testSavedSpecimenStoreRoundTripWritesPreviewAndManagedCopy {
    NSURL *directory = [self temporarySpecimenDirectory];
    SavedSpecimenStore *store = [[SavedSpecimenStore alloc]
        initWithDirectoryURL:[directory URLByAppendingPathComponent:@"store" isDirectory:YES]];
    NSURL *exportURL = [[directory URLByAppendingPathComponent:@"exports" isDirectory:YES]
                        URLByAppendingPathComponent:@"Saved Crystal.semspecimen"];

    SEMSpecimen *specimen = [self specimenForSavedFileTests];
    NSError *error = nil;
    XCTAssertTrue([store saveSpecimen:specimen
                         sourcePrompt:specimen.sourcePrompt
                                toURL:exportURL
                                error:&error],
                  @"Save failed: %@", error);

    NSFileManager *manager = [NSFileManager defaultManager];
    XCTAssertTrue([manager fileExistsAtPath:exportURL.path]);
    NSURL *previewURL = [store previewURLForSpecimenURL:exportURL];
    XCTAssertTrue([manager fileExistsAtPath:previewURL.path]);
    XCTAssertEqualObjects(previewURL.lastPathComponent, @"Saved Crystal-preview.png");

    NSData *data = [NSData dataWithContentsOfURL:exportURL];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    XCTAssertEqualObjects(payload[@"format"], @"SEMSimulatorSpecimen");
    XCTAssertEqualObjects(payload[@"name"], @"Saved Crystal");
    XCTAssertEqualObjects(payload[@"sourcePrompt"], @"salt crystals");
    XCTAssertNotNil(payload[@"previewPNG"]);
    XCTAssertEqualObjects(payload[@"recipe"][@"template"], @"crystal");
    XCTAssertNotNil(payload[@"savedAt"]);

    NSArray<SpecimenPreset *> *saved = store.savedPresets;
    XCTAssertEqual(saved.count, 1);
    SpecimenPreset *preset = saved.firstObject;
    XCTAssertEqualObjects(preset.category, @"SAVED");
    XCTAssertEqualObjects(preset.name, @"Saved Crystal");
    XCTAssertEqualObjects(preset.prompt, @"salt crystals");
    XCTAssertNotNil(preset.previewImage);
    XCTAssertNotNil([preset recipeRepresentation]);

    // A second store instance finds the managed copy on disk.
    SavedSpecimenStore *reloaded = [[SavedSpecimenStore alloc] initWithDirectoryURL:store.directoryURL];
    XCTAssertEqual(reloaded.savedPresets.count, 1);
    XCTAssertEqualObjects(reloaded.savedPresets.firstObject.identifier, preset.identifier);

    // Importing the exported file dedupes against the managed copy.
    NSError *importError = nil;
    SpecimenPreset *imported = [store importSpecimenFromURL:exportURL error:&importError];
    XCTAssertNotNil(imported, @"Import failed: %@", importError);
    XCTAssertEqualObjects(imported.identifier, preset.identifier);
    XCTAssertEqual(store.savedPresets.count, 1);

    // Moving the exported file away keeps the specimen in the offline list.
    XCTAssertTrue([manager removeItemAtURL:exportURL error:NULL]);
    XCTAssertTrue([manager removeItemAtURL:previewURL error:NULL]);
    XCTAssertEqual(reloaded.savedPresets.count, 1);

    [manager removeItemAtURL:directory error:NULL];
}

- (void)testSavedSpecimenStoreRejectsInvalidFiles {
    NSURL *directory = [self temporarySpecimenDirectory];
    SavedSpecimenStore *store = [[SavedSpecimenStore alloc]
        initWithDirectoryURL:[directory URLByAppendingPathComponent:@"store" isDirectory:YES]];
    NSURL *url = [directory URLByAppendingPathComponent:@"Broken.semspecimen"];
    NSFileManager *manager = [NSFileManager defaultManager];

    XCTAssertTrue([@"not a specimen" writeToURL:url
                                     atomically:YES
                                       encoding:NSUTF8StringEncoding
                                          error:NULL]);
    NSError *error = nil;
    XCTAssertNil([store importSpecimenFromURL:url error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(store.savedPresets.count, 0);

    NSDictionary *wrongFormat = @{@"format": @"OtherApp",
                                  @"name": @"Nope",
                                  @"recipe": @{@"name": @"Nope"}};
    NSData *wrongData = [NSJSONSerialization dataWithJSONObject:wrongFormat options:0 error:NULL];
    XCTAssertTrue([wrongData writeToURL:url atomically:YES]);
    error = nil;
    XCTAssertNil([store importSpecimenFromURL:url error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(store.savedPresets.count, 0);

    NSDictionary *missingRecipe = @{@"format": @"SEMSimulatorSpecimen",
                                    @"identifier": NSUUID.UUID.UUIDString,
                                    @"name": @"No Recipe"};
    NSData *missingData = [NSJSONSerialization dataWithJSONObject:missingRecipe options:0 error:NULL];
    XCTAssertTrue([missingData writeToURL:url atomically:YES]);
    error = nil;
    XCTAssertNil([store importSpecimenFromURL:url error:&error]);
    XCTAssertNotNil(error);
    XCTAssertEqual(store.savedPresets.count, 0);

    [manager removeItemAtURL:directory error:NULL];
}

- (void)testSavedSpecimenImportSanitizesIdentifier {
    NSURL *directory = [self temporarySpecimenDirectory];
    NSURL *storeDirectory = [directory URLByAppendingPathComponent:@"store" isDirectory:YES];
    SavedSpecimenStore *store = [[SavedSpecimenStore alloc] initWithDirectoryURL:storeDirectory];
    NSURL *url = [directory URLByAppendingPathComponent:@"Untrusted.semspecimen"];

    NSDictionary *payload = @{
        @"format": @"SEMSimulatorSpecimen",
        @"version": @1,
        @"identifier": @"../../escape",
        @"name": @"Untrusted",
        @"sourcePrompt": @"salt crystals",
        @"recipe": [[SemanticPromptParser recipeForPrompt:@"salt crystals" variation:9] dictionaryRepresentation],
        @"seed": @9
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:0 error:NULL];
    XCTAssertTrue([data writeToURL:url atomically:YES]);

    NSError *error = nil;
    SpecimenPreset *imported = [store importSpecimenFromURL:url error:&error];
    XCTAssertNotNil(imported, @"Import failed: %@", error);
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:imported.identifier],
                    @"Imported identifier was not a safe UUID: %@", imported.identifier);
    XCTAssertNotEqualObjects(imported.identifier, @"../../escape");

    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray<NSURL *> *managedFiles = [manager contentsOfDirectoryAtURL:storeDirectory
                                            includingPropertiesForKeys:nil
                                                               options:0
                                                                 error:NULL];
    XCTAssertEqual(managedFiles.count, 1);
    XCTAssertEqualObjects(managedFiles.firstObject.lastPathComponent,
                          [imported.identifier stringByAppendingPathExtension:SEMSpecimenFileExtension]);

    [manager removeItemAtURL:directory error:NULL];
}

- (void)testOfflineModelsIncludeSavedSpecimens {
    NSArray<SpecimenPreset *> *builtIns = [SpecimenLibrary builtInModels];
    NSArray<SpecimenPreset *> *saved = [SpecimenLibrary savedModels];
    NSArray<SpecimenPreset *> *offline = [SpecimenLibrary offlineModels];

    XCTAssertEqual(offline.count, builtIns.count + saved.count);
    for (NSUInteger index = 0; index < builtIns.count; index++) {
        XCTAssertEqualObjects(offline[index].identifier, builtIns[index].identifier);
    }
    for (NSUInteger index = 0; index < saved.count; index++) {
        XCTAssertEqualObjects(offline[builtIns.count + index].identifier, saved[index].identifier);
    }
}

- (void)testMainWindowSavesAndLoadsSpecimenFile {
    MainWindowController *controller = [[MainWindowController alloc] init];
    AISampleDrawer *drawer = [controller valueForKey:@"aiDrawer"];
    XCTAssertTrue(SEMWaitForCondition(^BOOL {
        return !drawer.isBusy;
    }, 20.0), @"Default specimen generation did not finish");

    NSURL *directory = [self temporarySpecimenDirectory];
    SavedSpecimenStore *store = [[SavedSpecimenStore alloc]
        initWithDirectoryURL:[directory URLByAppendingPathComponent:@"store" isDirectory:YES]];
    [controller setValue:store forKey:@"specimenStore"];

    SEMSpecimen *specimen = [self specimenForSavedFileTests];
    controller.engine.specimen = specimen;

    NSURL *exportURL = [[directory URLByAppendingPathComponent:@"export" isDirectory:YES]
                        URLByAppendingPathComponent:@"Saved Crystal.semspecimen"];
    NSError *error = nil;
    XCTAssertTrue([controller saveCurrentSpecimenToURL:exportURL error:&error],
                  @"Controller save failed: %@", error);
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:exportURL.path]);
    XCTAssertEqual(store.savedPresets.count, 1);

    // Replace the chamber contents so the load cannot pass by accident.
    SEMSpecimen *placeholder = [[SEMSpecimen alloc] init];
    placeholder.name = @"Placeholder";
    controller.engine.specimen = placeholder;

    [controller loadSpecimenFromFileURL:exportURL];
    BOOL loaded = SEMWaitForCondition(^BOOL {
        return [controller.engine.specimen.name isEqualToString:@"Saved Crystal"];
    }, 30.0);
    XCTAssertTrue(loaded, @"Specimen file was not loaded; current=%@", controller.engine.specimen.name);
    XCTAssertEqualObjects(controller.engine.specimen.sourcePrompt, @"salt crystals");
    XCTAssertEqual(store.savedPresets.count, 1);

    NSTimer *timer = [controller valueForKey:@"timer"];
    [timer invalidate];
    [controller.window close];
    [[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
}

@end
