#import <Cocoa/Cocoa.h>

@class MainWindowController;
@class SettingsWindowController;
@class HelpWindowController;

@interface AppDelegate : NSObject <NSApplicationDelegate>

@property (nonatomic, strong) MainWindowController *mainWindowController;
@property (nonatomic, strong) SettingsWindowController *settingsWindowController;
@property (nonatomic, strong) HelpWindowController *helpWindowController;

- (IBAction)showSettings:(id)sender;
- (IBAction)showHelp:(id)sender;
- (IBAction)saveMicrograph:(id)sender;
- (IBAction)saveSpecimen:(id)sender;
- (IBAction)loadSpecimenFromFile:(id)sender;
- (IBAction)zoomIn:(id)sender;
- (IBAction)zoomOut:(id)sender;
- (IBAction)resetZoom:(id)sender;
- (IBAction)loadSpecimenPreset:(id)sender;

@end
