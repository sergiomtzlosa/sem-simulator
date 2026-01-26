#import "AppDelegate.h"
#import "MainWindowController.h"
#import "SettingsWindowController.h"
#import "HelpWindowController.h"
#import "SavedSpecimenStore.h"
#import "SpecimenLibrary.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.mainWindowController = [[MainWindowController alloc] init];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(savedSpecimensChanged:)
                                                 name:SEMSavedSpecimensDidChangeNotification
                                               object:nil];
    [self buildMenu];
    [self.mainWindowController showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];

    if ([[NSProcessInfo processInfo].arguments containsObject:@"--selftest"]) {
        NSString *directory = [NSProcessInfo processInfo].environment[@"SEM_SELFTEST_DIR"] ?: @"/tmp/sem-selftest";
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.mainWindowController runSelfTestSavingToDirectory:directory];
        });
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}

- (void)buildMenu {
    NSMenu *mainMenu = [[NSMenu alloc] initWithTitle:@"Main Menu"];

    NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"SEM Simulator" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"SEM Simulator"];
    [appMenu addItemWithTitle:@"About SEM Simulator" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settings = [[NSMenuItem alloc] initWithTitle:@"Settings…" action:@selector(showSettings:) keyEquivalent:@","];
    settings.target = self;
    [appMenu addItem:settings];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *save = [[NSMenuItem alloc] initWithTitle:@"Save Micrograph…" action:@selector(saveMicrograph:) keyEquivalent:@"s"];
    save.target = self;
    [appMenu addItem:save];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit SEM Simulator" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo" action:@selector(redo:) keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    NSMenuItem *specimenItem = [[NSMenuItem alloc] initWithTitle:@"Specimen" action:nil keyEquivalent:@""];
    NSMenu *specimenMenu = [[NSMenu alloc] initWithTitle:@"Specimen"];
    NSMenuItem *generate = [[NSMenuItem alloc] initWithTitle:@"Open Specimen Generator" action:@selector(toggleAIDrawer:) keyEquivalent:@"d"];
    generate.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    generate.target = self.mainWindowController;
    [specimenMenu addItem:generate];

    NSMenuItem *saveSpecimen = [[NSMenuItem alloc] initWithTitle:@"Save Specimen…" action:@selector(saveSpecimen:) keyEquivalent:@"s"];
    saveSpecimen.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    saveSpecimen.target = self;
    [specimenMenu addItem:saveSpecimen];

    NSMenuItem *loadSpecimenFile = [[NSMenuItem alloc] initWithTitle:@"Load Specimen from File…" action:@selector(loadSpecimenFromFile:) keyEquivalent:@"o"];
    loadSpecimenFile.target = self;
    [specimenMenu addItem:loadSpecimenFile];
    [specimenMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *libraryHeader = [[NSMenuItem alloc] initWithTitle:@"Built-in Models (Offline)" action:nil keyEquivalent:@""];
    libraryHeader.enabled = NO;
    [specimenMenu addItem:libraryHeader];
    for (SpecimenPreset *preset in [SpecimenLibrary builtInModels]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:preset.name action:@selector(loadSpecimenPreset:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = preset;
        item.toolTip = [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail];
        [specimenMenu addItem:item];
    }

    NSArray<SpecimenPreset *> *saved = [SpecimenLibrary savedModels];
    if (saved.count > 0) {
        [specimenMenu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *savedHeader = [[NSMenuItem alloc] initWithTitle:@"Saved Specimens (Offline)" action:nil keyEquivalent:@""];
        savedHeader.enabled = NO;
        [specimenMenu addItem:savedHeader];
        for (SpecimenPreset *preset in saved) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:preset.name action:@selector(loadSpecimenPreset:) keyEquivalent:@""];
            item.target = self;
            item.representedObject = preset;
            item.toolTip = [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail];
            [specimenMenu addItem:item];
        }
    }
    specimenItem.submenu = specimenMenu;
    [mainMenu addItem:specimenItem];

    NSMenuItem *viewItem = [[NSMenuItem alloc] initWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];
    NSMenuItem *zoomIn = [[NSMenuItem alloc] initWithTitle:@"Zoom In" action:@selector(zoomIn:) keyEquivalent:@"+"];
    zoomIn.target = self;
    [viewMenu addItem:zoomIn];
    NSMenuItem *zoomOut = [[NSMenuItem alloc] initWithTitle:@"Zoom Out" action:@selector(zoomOut:) keyEquivalent:@"-"];
    zoomOut.target = self;
    [viewMenu addItem:zoomOut];
    NSMenuItem *resetZoom = [[NSMenuItem alloc] initWithTitle:@"Reset Magnification" action:@selector(resetZoom:) keyEquivalent:@"0"];
    resetZoom.target = self;
    [viewMenu addItem:resetZoom];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *toggleDrawer = [[NSMenuItem alloc] initWithTitle:@"Show/Hide Specimen Drawer" action:@selector(toggleAIDrawer:) keyEquivalent:@"d"];
    toggleDrawer.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    toggleDrawer.target = self.mainWindowController;
    [viewMenu addItem:toggleDrawer];
    viewItem.submenu = viewMenu;
    [mainMenu addItem:viewItem];

    NSMenuItem *windowItem = [[NSMenuItem alloc] initWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowItem.submenu = windowMenu;
    [mainMenu addItem:windowItem];
    NSApp.windowsMenu = windowMenu;

    NSMenuItem *helpItem = [[NSMenuItem alloc] initWithTitle:@"Help" action:nil keyEquivalent:@""];
    NSMenu *helpMenu = [[NSMenu alloc] initWithTitle:@"Help"];
    NSMenuItem *help = [[NSMenuItem alloc] initWithTitle:@"SEM Simulator Help" action:@selector(showHelp:) keyEquivalent:@"?"];
    help.target = self;
    [helpMenu addItem:help];
    helpItem.submenu = helpMenu;
    [mainMenu addItem:helpItem];
    NSApp.helpMenu = helpMenu;

    NSApp.mainMenu = mainMenu;
}

- (IBAction)showSettings:(id)sender {
    if (!self.settingsWindowController) {
        self.settingsWindowController = [[SettingsWindowController alloc] init];
    }
    [self.settingsWindowController showWindow:nil];
    [self.settingsWindowController.window makeKeyAndOrderFront:nil];
}

- (IBAction)saveMicrograph:(id)sender {
    [self.mainWindowController saveMicrograph:sender];
}

- (IBAction)saveSpecimen:(id)sender {
    [self.mainWindowController saveSpecimen:sender];
}

- (IBAction)loadSpecimenFromFile:(id)sender {
    [self.mainWindowController loadSpecimenFromFile:sender];
}

- (void)savedSpecimensChanged:(NSNotification *)notification {
    [self buildMenu];
}

- (IBAction)showHelp:(id)sender {
    if (!self.helpWindowController) {
        self.helpWindowController = [[HelpWindowController alloc] init];
    }
    [self.helpWindowController showWindow:nil];
    [self.helpWindowController.window makeKeyAndOrderFront:nil];
}

- (IBAction)zoomIn:(id)sender {
    [self.mainWindowController zoomIn:sender];
}

- (IBAction)zoomOut:(id)sender {
    [self.mainWindowController zoomOut:sender];
}

- (IBAction)resetZoom:(id)sender {
    [self.mainWindowController resetZoom:sender];
}

- (IBAction)loadSpecimenPreset:(id)sender {
    NSMenuItem *item = [sender isKindOfClass:[NSMenuItem class]] ? (NSMenuItem *)sender : nil;
    SpecimenPreset *preset = [item.representedObject isKindOfClass:[SpecimenPreset class]] ? item.representedObject : nil;
    if (preset) {
        [self.mainWindowController loadOfflineSpecimen:preset];
    }
}

@end
