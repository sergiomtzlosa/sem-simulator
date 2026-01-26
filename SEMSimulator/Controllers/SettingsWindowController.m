#import "SettingsWindowController.h"
#import "AppDelegate.h"
#import "MainWindowController.h"
#import "SEMPhysicsEngine.h"
#import "OpenCodeIntegration.h"
#import "SavedSpecimenStore.h"
#import "SpecimenLibrary.h"
#import "Theme.h"

@interface SettingsWindowController ()
@property (nonatomic, strong) NSTextField *openCodeURLField;
@property (nonatomic, strong) NSPopUpButton *openCodeModelPopup;
@property (nonatomic, strong) NSSecureTextField *openCodeKeyField;
@property (nonatomic, strong) NSTextField *openCodeStatusLabel;
@property (nonatomic, strong) NSButton *openCodeTestButton;
@property (nonatomic, strong) NSButton *openCodeRefreshButton;
@property (nonatomic, strong) NSTextField *maintenanceStatusLabel;
@property (nonatomic, strong) NSPopUpButton *builtInModelPopup;
@property (nonatomic, strong) NSTextField *builtInDetailLabel;
@property (nonatomic, strong) NSTextField *builtInStatusLabel;
@end

@implementation SettingsWindowController

- (instancetype)init {
    NSRect rect = NSMakeRect(0, 0, 640, 540);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SEM Simulator Settings";
    window.minSize = NSMakeSize(640, 540);
    window.backgroundColor = [Theme consoleBackground];
    window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    self = [super initWithWindow:window];
    if (self) {
        [self buildInterface];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(savedSpecimensChanged:)
                                                     name:SEMSavedSpecimensDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSTextField *)label:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [Theme labelFont];
    label.textColor = [Theme colorWithHex:0xD8D1C0];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSTextField *)fieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure {
    NSTextField *field = secure ? [[NSSecureTextField alloc] initWithFrame:NSZeroRect] : [[NSTextField alloc] initWithFrame:NSZeroRect];
    field.placeholderString = placeholder;
    field.font = [Theme monoFontOfSize:10];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    return field;
}

- (NSStackView *)rowWithLabel:(NSString *)text field:(NSView *)field {
    NSStackView *row = [[NSStackView alloc] init];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.distribution = NSStackViewDistributionFill;
    row.spacing = 8;
    row.translatesAutoresizingMaskIntoConstraints = NO;
    NSTextField *label = [self label:text];
    [label.widthAnchor constraintEqualToConstant:92].active = YES;
    [row addArrangedSubview:label];
    [row addArrangedSubview:field];
    [field.widthAnchor constraintGreaterThanOrEqualToConstant:300].active = YES;
    return row;
}

- (void)buildInterface {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = [Theme consoleBackground].CGColor;

    NSTextField *title = [NSTextField labelWithString:@"SEM SIMULATOR SETTINGS"];
    title.font = [Theme titleFont];
    title.textColor = [Theme colorWithHex:0xE2DACB];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *openCodeTitle = [self label:@"OPENCODE INTEGRATION"];
    openCodeTitle.font = [Theme titleFont];
    openCodeTitle.textColor = [Theme accentAmber];

    self.openCodeURLField = [self fieldWithPlaceholder:SEMOpenCodeDefaultURL secure:NO];
    self.openCodeModelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.openCodeModelPopup.controlSize = NSControlSizeRegular;
    self.openCodeModelPopup.cell.controlSize = NSControlSizeRegular;
    self.openCodeModelPopup.font = [NSFont systemFontOfSize:11];
    [Theme stylePopupButton:self.openCodeModelPopup];
    self.openCodeModelPopup.cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.openCodeModelPopup.cell.usesSingleLineMode = YES;
    self.openCodeModelPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.openCodeModelPopup.widthAnchor constraintGreaterThanOrEqualToConstant:420].active = YES;
    self.openCodeKeyField = (NSSecureTextField *)[self fieldWithPlaceholder:@"Optional password or API key (blank = no auth)" secure:YES];

    NSStackView *openCodeStack = [[NSStackView alloc] init];
    openCodeStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    openCodeStack.alignment = NSLayoutAttributeLeading;
    openCodeStack.distribution = NSStackViewDistributionFill;
    openCodeStack.spacing = 8;
    openCodeStack.translatesAutoresizingMaskIntoConstraints = NO;
    [openCodeStack setHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationVertical];
    [openCodeStack addArrangedSubview:[self rowWithLabel:@"SERVER URL" field:self.openCodeURLField]];
    [openCodeStack addArrangedSubview:[self rowWithLabel:@"MODEL" field:self.openCodeModelPopup]];
    [openCodeStack addArrangedSubview:[self rowWithLabel:@"PASSWORD" field:self.openCodeKeyField]];

    NSTextField *openCodeNote = [NSTextField labelWithString:@"Default URL: http://127.0.0.1:4096. MODEL is loaded from the server; AUTO prefers a local model. PASSWORD is optional; leave it blank when the server has no auth."];
    openCodeNote.font = [Theme smallFont];
    openCodeNote.textColor = [Theme colorWithHex:0x8F887A];
    openCodeNote.lineBreakMode = NSLineBreakByWordWrapping;
    openCodeNote.maximumNumberOfLines = 2;
    openCodeNote.translatesAutoresizingMaskIntoConstraints = NO;

    self.openCodeTestButton = [Theme consoleButtonWithTitle:@"TEST SERVER" target:self action:@selector(testOpenCode:)];
    self.openCodeRefreshButton = [Theme consoleButtonWithTitle:@"REFRESH MODELS" target:self action:@selector(refreshModels:)];
    NSButton *openCodeSave = [Theme consoleButtonWithTitle:@"SAVE OPENCODE" target:self action:@selector(saveSettings:)];
    NSButton *openCodeFile = [Theme consoleButtonWithTitle:@"LOAD PASSWORD FILE…" target:self action:@selector(loadOpenCodePasswordFile:)];
    self.openCodeTestButton.translatesAutoresizingMaskIntoConstraints = NO;
    self.openCodeRefreshButton.translatesAutoresizingMaskIntoConstraints = NO;
    openCodeSave.translatesAutoresizingMaskIntoConstraints = NO;
    openCodeFile.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *openCodeButtons = [[NSStackView alloc] init];
    openCodeButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    openCodeButtons.distribution = NSStackViewDistributionFill;
    openCodeButtons.spacing = 8;
    openCodeButtons.translatesAutoresizingMaskIntoConstraints = NO;
    [openCodeButtons addArrangedSubview:openCodeSave];
    [openCodeButtons addArrangedSubview:self.openCodeTestButton];
    [openCodeButtons addArrangedSubview:self.openCodeRefreshButton];
    [openCodeButtons addArrangedSubview:openCodeFile];

    self.openCodeStatusLabel = [NSTextField labelWithString:@"Default URL: http://127.0.0.1:4096 · model: auto · password: none"];
    self.openCodeStatusLabel.font = [Theme monoFontOfSize:9];
    self.openCodeStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.openCodeStatusLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.openCodeStatusLabel.maximumNumberOfLines = 2;
    self.openCodeStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *maintTitle = [self label:@"MAINTENANCE"];
    maintTitle.font = [Theme titleFont];
    maintTitle.textColor = [Theme accentAmber];

    NSButton *replace = [Theme consoleButtonWithTitle:@"REPLACE FILAMENT" target:self action:@selector(replaceFilament:)];
    NSButton *resetFault = [Theme consoleButtonWithTitle:@"RESET VACUUM FAULT" target:self action:@selector(resetFault:)];
    NSButton *clearContam = [Theme consoleButtonWithTitle:@"CLEAR CONTAMINATION" target:self action:@selector(clearContamination:)];
    NSButton *help = [Theme consoleButtonWithTitle:@"HELP…" target:self action:@selector(showHelp:)];
    NSStackView *maintButtons = [[NSStackView alloc] init];
    maintButtons.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    maintButtons.distribution = NSStackViewDistributionFill;
    maintButtons.spacing = 8;
    maintButtons.translatesAutoresizingMaskIntoConstraints = NO;
    [maintButtons addArrangedSubview:replace];
    [maintButtons addArrangedSubview:resetFault];
    [maintButtons addArrangedSubview:clearContam];
    [maintButtons addArrangedSubview:help];

    self.maintenanceStatusLabel = [NSTextField labelWithString:@"Ready."];
    self.maintenanceStatusLabel.font = [Theme monoFontOfSize:9];
    self.maintenanceStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.maintenanceStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *builtInTitle = [self label:@"OFFLINE MODELS (BUILT-IN + SAVED)"];
    builtInTitle.font = [Theme titleFont];
    builtInTitle.textColor = [Theme accentAmber];

    self.builtInModelPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.builtInModelPopup.controlSize = NSControlSizeRegular;
    self.builtInModelPopup.font = [NSFont systemFontOfSize:11];
    [Theme stylePopupButton:self.builtInModelPopup];
    self.builtInModelPopup.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    self.builtInModelPopup.cell.usesSingleLineMode = YES;
    self.builtInModelPopup.target = self;
    self.builtInModelPopup.action = @selector(builtInSelectionChanged:);
    self.builtInModelPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.builtInModelPopup.widthAnchor constraintGreaterThanOrEqualToConstant:420].active = YES;
    NSStackView *builtInRow = [self rowWithLabel:@"MODEL" field:self.builtInModelPopup];

    self.builtInDetailLabel = [NSTextField labelWithString:@"Built-in and saved models are always available offline."];
    self.builtInDetailLabel.font = [Theme monoFontOfSize:9];
    self.builtInDetailLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.builtInDetailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.builtInDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.builtInDetailLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                    forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSButton *builtInLoad = [Theme consoleButtonWithTitle:@"LOAD OFFLINE" target:self action:@selector(loadBuiltInModel:)];
    builtInLoad.toolTip = @"Synthesize and load the selected built-in model without contacting OpenCode.";
    builtInLoad.translatesAutoresizingMaskIntoConstraints = NO;
    [builtInLoad.widthAnchor constraintEqualToConstant:120].active = YES;

    self.builtInStatusLabel = [NSTextField labelWithString:@"Select a built-in or saved model and load it without contacting OpenCode."];
    self.builtInStatusLabel.font = [Theme monoFontOfSize:9];
    self.builtInStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.builtInStatusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.builtInStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    [self reloadOfflineModels];

    for (NSView *v in @[title, openCodeTitle, openCodeStack, openCodeNote, openCodeButtons,
                        self.openCodeStatusLabel, maintTitle, maintButtons, self.maintenanceStatusLabel,
                        builtInTitle, builtInRow, self.builtInDetailLabel, builtInLoad, self.builtInStatusLabel]) {
        [root addSubview:v];
    }

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:root.topAnchor constant:18],
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:22],

        [openCodeTitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:22],
        [openCodeTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [openCodeStack.topAnchor constraintEqualToAnchor:openCodeTitle.bottomAnchor constant:10],
        [openCodeStack.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [openCodeStack.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-22],
        [openCodeNote.topAnchor constraintEqualToAnchor:openCodeStack.bottomAnchor constant:8],
        [openCodeNote.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [openCodeNote.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],
        [openCodeButtons.topAnchor constraintEqualToAnchor:openCodeNote.bottomAnchor constant:10],
        [openCodeButtons.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [openCodeButtons.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],
        [self.openCodeStatusLabel.topAnchor constraintEqualToAnchor:openCodeButtons.bottomAnchor constant:8],
        [self.openCodeStatusLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.openCodeStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],

        [maintTitle.topAnchor constraintEqualToAnchor:self.openCodeStatusLabel.bottomAnchor constant:24],
        [maintTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [maintButtons.topAnchor constraintEqualToAnchor:maintTitle.bottomAnchor constant:10],
        [maintButtons.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [maintButtons.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],
        [self.maintenanceStatusLabel.topAnchor constraintEqualToAnchor:maintButtons.bottomAnchor constant:10],
        [self.maintenanceStatusLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.maintenanceStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],

        [builtInTitle.topAnchor constraintEqualToAnchor:self.maintenanceStatusLabel.bottomAnchor constant:22],
        [builtInTitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [builtInRow.topAnchor constraintEqualToAnchor:builtInTitle.bottomAnchor constant:10],
        [builtInRow.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [builtInRow.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-22],
        [self.builtInDetailLabel.topAnchor constraintEqualToAnchor:builtInRow.bottomAnchor constant:6],
        [self.builtInDetailLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.builtInDetailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],
        [builtInLoad.topAnchor constraintEqualToAnchor:self.builtInDetailLabel.bottomAnchor constant:10],
        [builtInLoad.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.builtInStatusLabel.topAnchor constraintEqualToAnchor:builtInLoad.bottomAnchor constant:10],
        [self.builtInStatusLabel.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [self.builtInStatusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-22],
        [self.builtInStatusLabel.bottomAnchor constraintLessThanOrEqualToAnchor:root.bottomAnchor constant:-18]
    ]];
}

- (void)showWindow:(id)sender {
    [self loadSettings];
    [super showWindow:sender];
    [self.window center];
    [self refreshModels:nil];
}

- (NSString *)selectedModelIdentifier {
    id value = self.openCodeModelPopup.selectedItem.representedObject;
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

- (BOOL)popupContainsModelIdentifier:(NSString *)identifier {
    for (NSMenuItem *item in self.openCodeModelPopup.itemArray) {
        if ([item.representedObject isKindOfClass:[NSString class]] &&
            [item.representedObject isEqualToString:identifier]) {
            return YES;
        }
    }
    return NO;
}

- (void)selectModelIdentifier:(NSString *)identifier {
    NSString *target = identifier ?: @"";
    for (NSInteger index = 0; index < self.openCodeModelPopup.numberOfItems; index++) {
        NSMenuItem *item = [self.openCodeModelPopup itemAtIndex:index];
        if ([item.representedObject isKindOfClass:[NSString class]] &&
            [item.representedObject isEqualToString:target]) {
            [self.openCodeModelPopup selectItemAtIndex:index];
            self.openCodeModelPopup.toolTip = target.length > 0 ? target : @"AUTO — prefer local model";
            return;
        }
    }
    if (self.openCodeModelPopup.numberOfItems > 0) {
        [self.openCodeModelPopup selectItemAtIndex:0];
        self.openCodeModelPopup.toolTip = @"AUTO — prefer local model";
    }
}

- (void)populateModelPopupWithModels:(NSArray<NSDictionary<NSString *, id> *> *)models {
    NSString *selected = [OpenCodeIntegration configuredModel] ?: @"";
    [self.openCodeModelPopup removeAllItems];

    [self.openCodeModelPopup addItemWithTitle:@"AUTO — prefer local model"];
    self.openCodeModelPopup.itemArray.lastObject.representedObject = @"";

    NSInteger lastScore = -1;
    for (NSDictionary *model in models) {
        NSString *identifier = [model[@"identifier"] isKindOfClass:[NSString class]] ? model[@"identifier"] : nil;
        if (identifier.length == 0) continue;
        NSInteger score = [model[@"score"] integerValue];
        if (lastScore != -1 && score != lastScore) {
            [self.openCodeModelPopup.menu addItem:[NSMenuItem separatorItem]];
        }
        lastScore = score;

        NSString *name = [model[@"name"] isKindOfClass:[NSString class]] ? model[@"name"] : identifier;
        [self.openCodeModelPopup addItemWithTitle:[NSString stringWithFormat:@"%@  ·  %@", name, identifier]];
        NSMenuItem *item = self.openCodeModelPopup.itemArray.lastObject;
        item.representedObject = identifier;
        item.toolTip = identifier;
    }

    if (selected.length > 0 && ![self popupContainsModelIdentifier:selected]) {
        [self.openCodeModelPopup.menu addItem:[NSMenuItem separatorItem]];
        [self.openCodeModelPopup addItemWithTitle:[NSString stringWithFormat:@"CONFIGURED  ·  %@", selected]];
        self.openCodeModelPopup.itemArray.lastObject.representedObject = selected;
    }

    [self selectModelIdentifier:selected];
}

- (void)refreshModels:(id)sender {
    NSString *url = [OpenCodeIntegration normalizedURLString:self.openCodeURLField.stringValue];
    NSString *password = self.openCodeKeyField.stringValue;
    self.openCodeRefreshButton.enabled = NO;
    self.openCodeStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.openCodeStatusLabel.stringValue = [NSString stringWithFormat:@"Loading models from %@…", url];

    __weak typeof(self) weakSelf = self;
    [OpenCodeIntegration fetchAvailableModelsForURL:url password:password
                                         completion:^(NSArray<NSDictionary<NSString *, id> *> *models, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.openCodeRefreshButton.enabled = YES;

        if (error) {
            [self populateModelPopupWithModels:@[]];
            self.openCodeStatusLabel.textColor = [Theme accentRed];
            self.openCodeStatusLabel.stringValue = error.localizedDescription;
            return;
        }

        [self populateModelPopupWithModels:models ?: @[]];
        self.openCodeStatusLabel.textColor = models.count > 0 ? [Theme accentGreen] : [Theme accentRed];
        self.openCodeStatusLabel.stringValue = models.count > 0
            ? [NSString stringWithFormat:@"Loaded %lu chat models from %@.", (unsigned long)models.count, url]
            : @"No chat models were reported by the server.";
    }];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *storedURL = [defaults stringForKey:SEMOpenCodeURLDefaultsKey];
    self.openCodeURLField.stringValue = storedURL ?: @"";
    self.openCodeKeyField.stringValue = [OpenCodeIntegration password] ?: @"";
    [self populateModelPopupWithModels:@[]];

    self.openCodeStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.openCodeStatusLabel.stringValue = [NSString stringWithFormat:@"Default URL: %@ · model: %@ · password: %@",
                                            SEMOpenCodeDefaultURL,
                                            [OpenCodeIntegration configuredModel] ?: @"auto",
                                            [OpenCodeIntegration hasPassword] ? @"set" : @"none"];
    self.maintenanceStatusLabel.stringValue = @"Ready.";
    self.builtInStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.builtInStatusLabel.stringValue = @"Select a model and load it without contacting OpenCode.";
}

- (SpecimenPreset *)selectedBuiltInPreset {
    id represented = self.builtInModelPopup.selectedItem.representedObject;
    return [represented isKindOfClass:[SpecimenPreset class]] ? represented : nil;
}

- (void)reloadOfflineModels {
    NSString *selectedIdentifier = [self selectedBuiltInPreset].identifier;
    [self.builtInModelPopup removeAllItems];

    NSArray<SpecimenPreset *> *builtIns = [SpecimenLibrary builtInModels];
    for (SpecimenPreset *preset in builtIns) {
        [self.builtInModelPopup addItemWithTitle:preset.name];
        NSMenuItem *item = self.builtInModelPopup.itemArray.lastObject;
        item.representedObject = preset;
        item.toolTip = [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail];
    }

    NSArray<SpecimenPreset *> *saved = [SpecimenLibrary savedModels];
    if (saved.count > 0) {
        [self.builtInModelPopup.menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"SAVED SPECIMENS" action:nil keyEquivalent:@""];
        header.enabled = NO;
        [self.builtInModelPopup.menu addItem:header];
        for (SpecimenPreset *preset in saved) {
            [self.builtInModelPopup addItemWithTitle:preset.name];
            NSMenuItem *item = self.builtInModelPopup.itemArray.lastObject;
            item.representedObject = preset;
            item.toolTip = [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail];
        }
    }

    NSInteger selection = 0;
    if (selectedIdentifier.length > 0) {
        for (NSMenuItem *item in self.builtInModelPopup.itemArray) {
            SpecimenPreset *preset = [item.representedObject isKindOfClass:[SpecimenPreset class]]
                ? item.representedObject
                : nil;
            if ([preset.identifier isEqualToString:selectedIdentifier]) {
                selection = [self.builtInModelPopup indexOfItem:item];
                break;
            }
        }
    }
    if (self.builtInModelPopup.numberOfItems > 0) {
        [self.builtInModelPopup selectItemAtIndex:selection];
    }
    [self builtInSelectionChanged:self.builtInModelPopup];
}

- (void)savedSpecimensChanged:(NSNotification *)notification {
    [self reloadOfflineModels];
}

- (void)builtInSelectionChanged:(id)sender {
    SpecimenPreset *preset = [self selectedBuiltInPreset];
    self.builtInDetailLabel.stringValue = preset
        ? [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail]
        : @"Built-in and saved models are always available offline.";
}

- (void)loadBuiltInModel:(id)sender {
    SpecimenPreset *preset = [self selectedBuiltInPreset];
    if (!preset) {
        self.builtInStatusLabel.textColor = [Theme accentRed];
        self.builtInStatusLabel.stringValue = @"Select an offline model first.";
        NSBeep();
        return;
    }
    AppDelegate *delegate = (AppDelegate *)NSApp.delegate;
    [delegate.mainWindowController loadOfflineSpecimen:preset];
    self.builtInStatusLabel.textColor = [Theme accentGreen];
    self.builtInStatusLabel.stringValue = [NSString stringWithFormat:@"Requested %@. The chamber will reload.", preset.name];
}

- (void)saveSettings:(id)sender {
    NSString *url = [OpenCodeIntegration normalizedURLString:self.openCodeURLField.stringValue];
    [OpenCodeIntegration setServerURL:url];
    [OpenCodeIntegration setConfiguredModel:[self selectedModelIdentifier]];

    NSError *openCodeError = nil;
    [OpenCodeIntegration setPassword:self.openCodeKeyField.stringValue error:&openCodeError];
    self.openCodeStatusLabel.textColor = openCodeError ? [Theme accentRed] : [Theme colorWithHex:0x8F887A];
    if (openCodeError) {
        self.openCodeStatusLabel.stringValue = openCodeError.localizedDescription;
    } else {
        NSString *model = [OpenCodeIntegration configuredModel] ?: @"auto";
        NSString *password = [OpenCodeIntegration hasPassword] ? @"set" : @"none";
        self.openCodeStatusLabel.stringValue = [NSString stringWithFormat:@"Saved. URL: %@ · model: %@ · password: %@", url, model, password];
    }
}

- (void)testOpenCode:(id)sender {
    NSString *url = [OpenCodeIntegration normalizedURLString:self.openCodeURLField.stringValue];
    NSString *password = self.openCodeKeyField.stringValue;
    self.openCodeStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.openCodeStatusLabel.stringValue = [NSString stringWithFormat:@"Testing %@…", url];
    self.openCodeTestButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    [OpenCodeIntegration testServerURL:url password:password completion:^(BOOL ok, NSString *message) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.openCodeTestButton.enabled = YES;
        self.openCodeStatusLabel.textColor = ok ? [Theme accentGreen] : [Theme accentRed];
        self.openCodeStatusLabel.stringValue = message;
    }];
}

- (void)loadOpenCodePasswordFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Load Password";
    panel.message = @"Choose the OpenCode password file, for example .opencode/password.";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL == nil) return;
        NSError *readError = nil;
        NSString *contents = [NSString stringWithContentsOfURL:panel.URL encoding:NSUTF8StringEncoding error:&readError];
        if (!contents) {
            self.openCodeStatusLabel.textColor = [Theme accentRed];
            self.openCodeStatusLabel.stringValue = readError.localizedDescription ?: @"Could not read the password file.";
            return;
        }
        NSString *password = [contents stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (password.length == 0) {
            self.openCodeKeyField.stringValue = @"";
            self.openCodeStatusLabel.textColor = [Theme colorWithHex:0x8F887A];
            self.openCodeStatusLabel.stringValue = [NSString stringWithFormat:@"%@ is empty; password cleared. Press SAVE OPENCODE to disable auth.", panel.URL.lastPathComponent];
            return;
        }
        self.openCodeKeyField.stringValue = password;
        self.openCodeStatusLabel.textColor = [Theme accentGreen];
        self.openCodeStatusLabel.stringValue = [NSString stringWithFormat:@"Loaded password from %@. Press SAVE OPENCODE to store it.", panel.URL.lastPathComponent];
    }];
}

- (void)showHelp:(id)sender {
    [(AppDelegate *)NSApp.delegate showHelp:sender];
}

- (SEMPhysicsEngine *)engine {
    AppDelegate *delegate = (AppDelegate *)NSApp.delegate;
    return delegate.mainWindowController.engine;
}

- (void)replaceFilament:(id)sender {
    [self.engine replaceFilament];
    self.maintenanceStatusLabel.stringValue = @"Filament replaced.";
}

- (void)resetFault:(id)sender {
    [self.engine resetFault];
    self.maintenanceStatusLabel.stringValue = @"Vacuum fault reset.";
}

- (void)clearContamination:(id)sender {
    [self.engine resetContamination];
    self.maintenanceStatusLabel.stringValue = @"Contamination map cleared.";
}

@end
