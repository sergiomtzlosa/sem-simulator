#import <Cocoa/Cocoa.h>

@class SEMPhysicsEngine;
@class SpecimenPreset;

NS_ASSUME_NONNULL_BEGIN

@interface MainWindowController : NSWindowController

@property (nonatomic, readonly) SEMPhysicsEngine *engine;

- (IBAction)saveMicrograph:(id)sender;
- (IBAction)saveSpecimen:(id)sender;
- (IBAction)loadSpecimenFromFile:(id)sender;
- (BOOL)saveCurrentSpecimenToURL:(NSURL *)url error:(NSError **)error;
- (void)loadSpecimenFromFileURL:(NSURL *)url;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)resetZoom:(id)sender;
- (IBAction)toggleAIDrawer:(nullable id)sender;
- (void)loadOfflineSpecimen:(SpecimenPreset *)preset;
- (void)runSelfTestSavingToDirectory:(NSString *)directory;

@end

NS_ASSUME_NONNULL_END
