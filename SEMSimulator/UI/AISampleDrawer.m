#import "AISampleDrawer.h"
#import <QuartzCore/QuartzCore.h>
#import "SEMSpecimen.h"
#import "SavedSpecimenStore.h"
#import "SpecimenLibrary.h"
#import "Theme.h"

@interface AISampleDrawer ()
@property (nonatomic, strong) NSTextField *promptField;
@property (nonatomic, strong) NSButton *generateButton;
@property (nonatomic, strong) NSButton *variationButton;
@property (nonatomic, strong) NSPopUpButton *builtInPopup;
@property (nonatomic, strong) NSButton *builtInLoadButton;
@property (nonatomic, strong) NSTextField *builtInDetailLabel;
@property (nonatomic, strong) NSButton *saveSpecimenButton;
@property (nonatomic, strong) NSButton *loadSpecimenFileButton;
@property (nonatomic, strong) NSImageView *thumbnailView;
@property (nonatomic, strong) NSTextField *summaryLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@end

@implementation AISampleDrawer

- (NSButton *)blackTitleButtonWithTitle:(NSString *)title action:(SEL)action {
    NSButton *button = [Theme consoleButtonWithTitle:title target:self action:action];
    button.contentTintColor = [NSColor blackColor];
    button.attributedTitle = [[NSAttributedString alloc] initWithString:title
                                                             attributes:@{
        NSForegroundColorAttributeName: [NSColor blackColor],
        NSFontAttributeName: [Theme condensedFontOfSize:10 weight:NSFontWeightSemibold]
    }];
    return button;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [Theme colorWithHex:0x1E1F1A].CGColor;
        self.layer.borderColor = [Theme colorWithHex:0x5D584D].CGColor;
        self.layer.borderWidth = 1.0;
        self.layer.cornerRadius = 6.0;
        [self buildInterface];
    }
    return self;
}

- (void)buildInterface {
    NSTextField *title = [NSTextField labelWithString:@"SPECIMEN GENERATOR"];
    title.font = [Theme titleFont];
    title.textColor = [Theme colorWithHex:0xD9D2C3];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField *subtitle = [NSTextField labelWithString:@"OPENCODE AI + OFFLINE MODELS  ->  HEIGHT / NORMAL / Z MAPS"];
    subtitle.font = [Theme smallFont];
    subtitle.textColor = [Theme colorWithHex:0x8F887A];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *settings = [self blackTitleButtonWithTitle:@"SET" action:@selector(settingsPressed:)];
    settings.translatesAutoresizingMaskIntoConstraints = NO;
    [settings.widthAnchor constraintEqualToConstant:48].active = YES;

    self.promptField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.promptField.placeholderAttributedString =
        [[NSAttributedString alloc] initWithString:@"Describe a specimen, e.g. fractured titanium alloy"
                                        attributes:@{
                                            NSForegroundColorAttributeName: [NSColor darkGrayColor],
                                            NSFontAttributeName: [Theme monoFontOfSize:10],
                                        }];
    self.promptField.font = [Theme monoFontOfSize:10];
    self.promptField.textColor = [NSColor blackColor];
    self.promptField.backgroundColor = [NSColor whiteColor];
    self.promptField.drawsBackground = YES;
    self.promptField.bezeled = YES;
    self.promptField.focusRingType = NSFocusRingTypeExterior;
    self.promptField.target = self;
    self.promptField.action = @selector(generatePressed:);
    self.promptField.translatesAutoresizingMaskIntoConstraints = NO;

    self.generateButton = [self blackTitleButtonWithTitle:@"GENERATE + LOAD" action:@selector(generatePressed:)];
    self.generateButton.toolTip = @"Ask OpenCode for a specimen recipe and load the synthesized maps into the chamber.";
    self.generateButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.generateButton.widthAnchor constraintEqualToConstant:132].active = YES;

    self.variationButton = [self blackTitleButtonWithTitle:@"VARIATION" action:@selector(variationPressed:)];
    self.variationButton.toolTip = @"Generate a new variation of the described specimen.";
    self.variationButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.variationButton.widthAnchor constraintEqualToConstant:82].active = YES;

    NSTextField *builtInLabel = [NSTextField labelWithString:@"OFFLINE"];
    builtInLabel.font = [Theme labelFont];
    builtInLabel.textColor = [Theme colorWithHex:0xD9D2C3];
    builtInLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.builtInPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.builtInPopup.controlSize = NSControlSizeSmall;
    self.builtInPopup.font = [Theme smallFont];
    [Theme stylePopupButton:self.builtInPopup];
    self.builtInPopup.layer.backgroundColor = [NSColor whiteColor].CGColor;
    self.builtInPopup.contentTintColor = [NSColor blackColor];
    self.builtInPopup.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    self.builtInPopup.cell.usesSingleLineMode = YES;
    self.builtInPopup.target = self;
    self.builtInPopup.action = @selector(builtInSelectionChanged:);
    self.builtInPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [self.builtInPopup.widthAnchor constraintEqualToConstant:190].active = YES;

    self.builtInLoadButton = [self blackTitleButtonWithTitle:@"LOAD OFFLINE" action:@selector(loadBuiltInPressed:)];
    self.builtInLoadButton.toolTip = @"Synthesize and load the selected built-in model without contacting OpenCode.";
    self.builtInLoadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.builtInLoadButton.widthAnchor constraintEqualToConstant:96].active = YES;

    self.builtInDetailLabel = [NSTextField labelWithString:@"Built-in and saved models are available offline."];
    self.builtInDetailLabel.font = [Theme monoFontOfSize:9];
    self.builtInDetailLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.builtInDetailLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.builtInDetailLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.builtInDetailLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                     forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.saveSpecimenButton = [self blackTitleButtonWithTitle:@"SAVE SPECIMEN" action:@selector(saveSpecimenPressed:)];
    self.saveSpecimenButton.toolTip = @"Save the generated specimen, its recipe, and its preview image.";
    self.saveSpecimenButton.enabled = NO;
    self.saveSpecimenButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.loadSpecimenFileButton = [self blackTitleButtonWithTitle:@"LOAD FILE…" action:@selector(loadSpecimenFilePressed:)];
    self.loadSpecimenFileButton.toolTip = @"Load a saved .semspecimen file and add it to the offline list.";
    self.loadSpecimenFileButton.translatesAutoresizingMaskIntoConstraints = NO;

    self.thumbnailView = [[NSImageView alloc] initWithFrame:NSZeroRect];
    self.thumbnailView.imageScaling = NSImageScaleProportionallyUpOrDown;
    self.thumbnailView.wantsLayer = YES;
    self.thumbnailView.layer.backgroundColor = [Theme colorWithHex:0x0B0C0A].CGColor;
    self.thumbnailView.layer.borderColor = [Theme colorWithHex:0x5D584D].CGColor;
    self.thumbnailView.layer.borderWidth = 1.0;
    self.thumbnailView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.thumbnailView.widthAnchor constraintEqualToConstant:108].active = YES;
    [self.thumbnailView.heightAnchor constraintEqualToConstant:108].active = YES;

    self.summaryLabel = [NSTextField labelWithString:@"No specimen yet.\nGenerate with OpenCode or load a built-in model offline.\nMaps are synthesized locally in both cases."];
    self.summaryLabel.font = [Theme monoFontOfSize:9];
    self.summaryLabel.textColor = [Theme colorWithHex:0xBDB5A5];
    self.summaryLabel.maximumNumberOfLines = 4;
    self.summaryLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.statusLabel = [NSTextField labelWithString:@"OpenCode recipe engine and offline models ready."];
    self.statusLabel.font = [Theme smallFont];
    self.statusLabel.textColor = [Theme colorWithHex:0x8F887A];
    self.statusLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                               forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.spinner = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [self.spinner.widthAnchor constraintEqualToConstant:16].active = YES;
    [self.spinner.heightAnchor constraintEqualToConstant:16].active = YES;

    NSStackView *fileButtons = [[NSStackView alloc] init];
    fileButtons.orientation = NSUserInterfaceLayoutOrientationVertical;
    fileButtons.alignment = NSLayoutAttributeLeading;
    fileButtons.distribution = NSStackViewDistributionFill;
    fileButtons.spacing = 6;
    fileButtons.translatesAutoresizingMaskIntoConstraints = NO;
    [fileButtons addArrangedSubview:self.saveSpecimenButton];
    [fileButtons addArrangedSubview:self.loadSpecimenFileButton];

    [self addSubview:title];
    [self addSubview:subtitle];
    [self addSubview:settings];
    [self addSubview:self.promptField];
    [self addSubview:self.generateButton];
    [self addSubview:self.variationButton];
    [self addSubview:builtInLabel];
    [self addSubview:self.builtInPopup];
    [self addSubview:self.builtInLoadButton];
    [self addSubview:self.builtInDetailLabel];
    [self addSubview:self.thumbnailView];
    [self addSubview:self.summaryLabel];
    [self addSubview:fileButtons];
    [self addSubview:self.statusLabel];
    [self addSubview:self.spinner];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.topAnchor constant:10],
        [title.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [subtitle.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:-1],
        [settings.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
        [settings.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],

        [self.promptField.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:10],
        [self.promptField.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.promptField.trailingAnchor constraintEqualToAnchor:self.generateButton.leadingAnchor constant:-8],
        [self.generateButton.centerYAnchor constraintEqualToAnchor:self.promptField.centerYAnchor],
        [self.generateButton.trailingAnchor constraintEqualToAnchor:self.variationButton.leadingAnchor constant:-4],
        [self.variationButton.centerYAnchor constraintEqualToAnchor:self.promptField.centerYAnchor],
        [self.variationButton.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],

        [builtInLabel.topAnchor constraintEqualToAnchor:self.promptField.bottomAnchor constant:9],
        [builtInLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.builtInPopup.leadingAnchor constraintEqualToAnchor:builtInLabel.trailingAnchor constant:6],
        [self.builtInPopup.centerYAnchor constraintEqualToAnchor:builtInLabel.centerYAnchor],
        [self.builtInLoadButton.leadingAnchor constraintEqualToAnchor:self.builtInPopup.trailingAnchor constant:6],
        [self.builtInLoadButton.centerYAnchor constraintEqualToAnchor:builtInLabel.centerYAnchor],
        [self.builtInDetailLabel.leadingAnchor constraintEqualToAnchor:self.builtInLoadButton.trailingAnchor constant:10],
        [self.builtInDetailLabel.centerYAnchor constraintEqualToAnchor:builtInLabel.centerYAnchor],
        [self.builtInDetailLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-14],

        [self.thumbnailView.topAnchor constraintEqualToAnchor:builtInLabel.bottomAnchor constant:10],
        [self.thumbnailView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.summaryLabel.leadingAnchor constraintEqualToAnchor:self.thumbnailView.trailingAnchor constant:14],
        [self.summaryLabel.topAnchor constraintEqualToAnchor:self.thumbnailView.topAnchor],
        [self.summaryLabel.trailingAnchor constraintLessThanOrEqualToAnchor:fileButtons.leadingAnchor constant:-12],
        [fileButtons.topAnchor constraintEqualToAnchor:self.thumbnailView.topAnchor],
        [fileButtons.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [fileButtons.widthAnchor constraintEqualToConstant:120],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.thumbnailView.bottomAnchor constant:8],
        [self.statusLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-36],
        [self.statusLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-10],
        [self.spinner.leadingAnchor constraintEqualToAnchor:self.statusLabel.trailingAnchor constant:6],
        [self.spinner.centerYAnchor constraintEqualToAnchor:self.statusLabel.centerYAnchor],
        [self.spinner.trailingAnchor constraintLessThanOrEqualToAnchor:self.trailingAnchor constant:-14]
    ]];

    [self reloadOfflineModels];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(savedSpecimensChanged:)
                                                 name:SEMSavedSpecimensDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)reloadOfflineModels {
    NSString *selectedIdentifier = [self selectedBuiltInPreset].identifier;

    [self.builtInPopup removeAllItems];
    NSArray<SpecimenPreset *> *builtIns = [SpecimenLibrary builtInModels];
    for (SpecimenPreset *preset in builtIns) {
        [self.builtInPopup addItemWithTitle:preset.name];
        NSMenuItem *item = self.builtInPopup.itemArray.lastObject;
        item.representedObject = preset;
        item.toolTip = [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail];
    }

    NSArray<SpecimenPreset *> *saved = [SpecimenLibrary savedModels];
    if (saved.count > 0) {
        [self.builtInPopup.menu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"SAVED SPECIMENS" action:nil keyEquivalent:@""];
        header.enabled = NO;
        [self.builtInPopup.menu addItem:header];
        for (SpecimenPreset *preset in saved) {
            [self.builtInPopup addItemWithTitle:preset.name];
            NSMenuItem *item = self.builtInPopup.itemArray.lastObject;
            item.representedObject = preset;
            item.toolTip = [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail];
        }
    }

    NSInteger selection = 0;
    if (selectedIdentifier.length > 0) {
        for (NSMenuItem *item in self.builtInPopup.itemArray) {
            SpecimenPreset *preset = [item.representedObject isKindOfClass:[SpecimenPreset class]]
                ? item.representedObject
                : nil;
            if ([preset.identifier isEqualToString:selectedIdentifier]) {
                selection = [self.builtInPopup indexOfItem:item];
                break;
            }
        }
    }
    if (self.builtInPopup.numberOfItems > 0) {
        [self.builtInPopup selectItemAtIndex:selection];
    }
    [self builtInSelectionChanged:self.builtInPopup];
}

- (void)savedSpecimensChanged:(NSNotification *)notification {
    [self reloadOfflineModels];
}

- (void)setBusy:(BOOL)busy {
    _busy = busy;
    self.generateButton.enabled = !busy;
    self.variationButton.enabled = !busy;
    self.promptField.enabled = !busy;
    self.builtInPopup.enabled = !busy;
    self.builtInLoadButton.enabled = !busy;
    self.saveSpecimenButton.enabled = !busy && self.specimen != nil;
    self.loadSpecimenFileButton.enabled = !busy;
    if (busy) [self.spinner startAnimation:nil];
    else [self.spinner stopAnimation:nil];
}

- (void)setStatusText:(NSString *)text {
    self.statusLabel.stringValue = text ?: @"";
}

- (void)setSpecimen:(SEMSpecimen *)specimen {
    _specimen = specimen;
    self.saveSpecimenButton.enabled = !self.busy && specimen != nil;
    if (!specimen) {
        self.thumbnailView.image = [self selectedBuiltInPreset].previewImage;
        self.summaryLabel.stringValue = @"No specimen yet.\nGenerate with OpenCode or load a built-in model offline.\nMaps are synthesized locally in both cases.";
        return;
    }
    self.thumbnailView.image = specimen.thumbnail;
    NSString *conductive = specimen.conductive ? @"YES" : @"NO";
    NSString *coating = specimen.coatingRecommended ? @"RECOMMENDED" : @"OPTIONAL";
    self.summaryLabel.stringValue = [NSString stringWithFormat:@"%@\nTEMPLATE: %@   Z: %.1f\nCONDUCTIVE: %@   COATING: %@\nMAPS: HEIGHT / NORMAL / Z",
                                     specimen.name.uppercaseString,
                                     specimen.templateName.uppercaseString,
                                     specimen.meanZ,
                                     conductive,
                                     coating];
}

- (NSString *)currentPrompt {
    return [self.promptField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (SpecimenPreset *)selectedBuiltInPreset {
    id represented = self.builtInPopup.selectedItem.representedObject;
    return [represented isKindOfClass:[SpecimenPreset class]] ? represented : nil;
}

- (void)builtInSelectionChanged:(id)sender {
    SpecimenPreset *preset = [self selectedBuiltInPreset];
    self.builtInDetailLabel.stringValue = preset
        ? [NSString stringWithFormat:@"%@ · %@", preset.category, preset.detail]
        : @"Built-in and saved models are available offline.";
    if (preset.previewImage) {
        self.thumbnailView.image = preset.previewImage;
    } else if (self.specimen) {
        self.thumbnailView.image = self.specimen.thumbnail;
    }
}

- (void)requestGeneration {
    if (self.busy) return;
    NSString *prompt = [self currentPrompt];
    if (prompt.length == 0) {
        [self setStatusText:@"Enter a specimen description first."];
        NSBeep();
        return;
    }
    [self.delegate aiDrawerDidRequestGenerate:prompt variation:(NSUInteger)arc4random()];
}

- (void)generatePressed:(id)sender {
    [self requestGeneration];
}

- (void)variationPressed:(id)sender {
    [self requestGeneration];
}

- (void)loadBuiltInPressed:(id)sender {
    if (self.busy) return;
    SpecimenPreset *preset = [self selectedBuiltInPreset];
    if (!preset) {
        [self setStatusText:@"Select an offline model first."];
        NSBeep();
        return;
    }
    [self.delegate aiDrawerDidRequestLoadBuiltInModel:preset];
}

- (void)saveSpecimenPressed:(id)sender {
    if (self.busy || !self.specimen) {
        [self setStatusText:@"Generate or load a specimen before saving."];
        NSBeep();
        return;
    }
    [self.delegate aiDrawerDidRequestSaveSpecimen:self];
}

- (void)loadSpecimenFilePressed:(id)sender {
    if (self.busy) return;
    [self.delegate aiDrawerDidRequestLoadSpecimenFile:self];
}

- (void)settingsPressed:(id)sender {
    [self.delegate aiDrawerDidRequestSettings:self];
}

@end
