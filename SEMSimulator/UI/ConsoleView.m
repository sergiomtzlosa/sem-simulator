#import "ConsoleView.h"
#import "SEMPhysicsEngine.h"
#import "SEMScaleMath.h"
#import "Theme.h"
#import "PanelView.h"
#import "PressureGaugeView.h"
#import "RockerSwitchControl.h"
#import "RotaryKnobControl.h"
#import "VoltageSelectorView.h"
#import "LEDIndicatorView.h"

typedef NS_ENUM(NSInteger, SEMKnobTag) {
    SEMKnobTagFilament = 100,
    SEMKnobTagSpot,
    SEMKnobTagMagnification,
    SEMKnobTagFocusCoarse,
    SEMKnobTagFocusFine,
    SEMKnobTagStigX,
    SEMKnobTagStigY,
    SEMKnobTagWorkingDistance,
    SEMKnobTagStageX,
    SEMKnobTagStageY,
    SEMKnobTagStageZ,
    SEMKnobTagTilt,
    SEMKnobTagRotation,
    SEMKnobTagBrightness,
    SEMKnobTagContrast,
    SEMKnobTagScanSpeed
};

typedef NS_ENUM(NSInteger, SEMRockerTag) {
    SEMRockerTagRP = 200,
    SEMRockerTagDP,
    SEMRockerTagHV,
    SEMRockerTagGold
};

@interface ConsoleView ()
@property (nonatomic, strong) PressureGaugeView *gauge;
@property (nonatomic, strong) RockerSwitchControl *rpSwitch;
@property (nonatomic, strong) RockerSwitchControl *dpSwitch;
@property (nonatomic, strong) RockerSwitchControl *hvSwitch;
@property (nonatomic, strong) RockerSwitchControl *goldSwitch;
@property (nonatomic, strong) VoltageSelectorView *voltageSelector;
@property (nonatomic, strong) RotaryKnobControl *filamentKnob;
@property (nonatomic, strong) RotaryKnobControl *spotKnob;
@property (nonatomic, strong) RotaryKnobControl *magnificationKnob;
@property (nonatomic, strong) RotaryKnobControl *focusCoarseKnob;
@property (nonatomic, strong) RotaryKnobControl *focusFineKnob;
@property (nonatomic, strong) RotaryKnobControl *stigXKnob;
@property (nonatomic, strong) RotaryKnobControl *stigYKnob;
@property (nonatomic, strong) RotaryKnobControl *workingDistanceKnob;
@property (nonatomic, strong) RotaryKnobControl *stageXKnob;
@property (nonatomic, strong) RotaryKnobControl *stageYKnob;
@property (nonatomic, strong) RotaryKnobControl *stageZKnob;
@property (nonatomic, strong) RotaryKnobControl *tiltKnob;
@property (nonatomic, strong) RotaryKnobControl *rotationKnob;
@property (nonatomic, strong) RotaryKnobControl *brightnessKnob;
@property (nonatomic, strong) RotaryKnobControl *contrastKnob;
@property (nonatomic, strong) RotaryKnobControl *scanSpeedKnob;
@property (nonatomic, strong) NSSegmentedControl *detectorControl;
@property (nonatomic, strong) NSSegmentedControl *scanControl;
@property (nonatomic, strong) NSSegmentedControl *phosphorControl;
@property (nonatomic, strong) NSSegmentedControl *unitsControl;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTextField *vacuumReadout;
@property (nonatomic, strong) NSTextField *emissionReadout;
@property (nonatomic, strong) NSTextField *filamentReadout;
@property (nonatomic, strong) LEDIndicatorView *vacuumLED;
@property (nonatomic, strong) LEDIndicatorView *hvLED;
@property (nonatomic, strong) LEDIndicatorView *beamLED;
@property (nonatomic, strong) LEDIndicatorView *faultLED;
@property (nonatomic, assign) BOOL torr;
@property (nonatomic, assign) SEMPhosphorMode phosphorMode;
@end

@implementation ConsoleView

- (instancetype)initWithEngine:(SEMPhysicsEngine *)engine {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _engine = engine;
        _torr = NO;
        _phosphorMode = SEMPhosphorModeGreen;
        [self buildInterface];
        [self refreshFromEngine];
    }
    return self;
}

- (void)buildInterface {
    NSStackView *root = [[NSStackView alloc] init];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.distribution = NSStackViewDistributionFill;
    root.spacing = 8;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:self.topAnchor constant:8],
        [root.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [root.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-8]
    ]];

    [root addArrangedSubview:[self buildHeaderPanel]];
    [root addArrangedSubview:[self buildVacuumPanel]];
    [root addArrangedSubview:[self buildOpticsPanel]];
    [root addArrangedSubview:[self buildStagePanel]];
    [root addArrangedSubview:[self buildDetectorPanel]];
}

- (PanelView *)panelWithTitle:(NSString *)title height:(CGFloat)height {
    PanelView *panel = [[PanelView alloc] initWithFrame:NSZeroRect];
    panel.title = title;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    [panel.heightAnchor constraintEqualToConstant:height].active = YES;
    [panel.widthAnchor constraintEqualToConstant:584].active = YES;
    return panel;
}

- (NSStackView *)contentStackInPanel:(PanelView *)panel topInset:(CGFloat)topInset {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:panel.topAnchor constant:topInset],
        [stack.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [stack.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-14],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:panel.bottomAnchor constant:-8]
    ]];
    return stack;
}

- (NSStackView *)horizontalStack {
    NSStackView *stack = [[NSStackView alloc] init];
    stack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    stack.alignment = NSLayoutAttributeCenterY;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    return stack;
}

- (NSTextField *)label:(NSString *)text size:(CGFloat)size color:(NSColor *)color {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [Theme condensedFontOfSize:size weight:NSFontWeightSemibold];
    label.textColor = color;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (NSTextField *)valueLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [Theme valueFont];
    label.textColor = [Theme colorWithHex:0x27241E];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    return label;
}

- (PanelView *)buildHeaderPanel {
    PanelView *panel = [self panelWithTitle:@"" height:50];
    NSStackView *row = [self horizontalStack];
    row.spacing = 10;

    NSTextField *title = [self label:@"SEM SIMULATOR" size:17 color:[Theme colorWithHex:0x27241D]];
    NSTextField *subtitle = [self label:@"SCANNING ELECTRON MICROSCOPE" size:7.5 color:[Theme colorWithHex:0x5A554A]];
    NSStackView *titleStack = [[NSStackView alloc] init];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = -2;
    [titleStack addArrangedSubview:title];
    [titleStack addArrangedSubview:subtitle];

    NSView *spacer = [[NSView alloc] init];
    spacer.translatesAutoresizingMaskIntoConstraints = NO;
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.statusLabel = [NSTextField labelWithString:@"SYSTEM READY"];
    self.statusLabel.font = [Theme monoFontOfSize:8.5];
    self.statusLabel.textColor = [Theme colorWithHex:0x2E4D31];
    self.statusLabel.alignment = NSTextAlignmentRight;
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;

    NSButton *saveButton = [Theme consoleButtonWithTitle:@"SAVE" target:self action:@selector(savePressed:)];
    NSButton *helpButton = [Theme consoleButtonWithTitle:@"HELP" target:self action:@selector(helpPressed:)];
    NSButton *settingsButton = [Theme consoleButtonWithTitle:@"SET" target:self action:@selector(settingsPressed:)];
    [saveButton.widthAnchor constraintEqualToConstant:54].active = YES;
    [helpButton.widthAnchor constraintEqualToConstant:48].active = YES;
    [settingsButton.widthAnchor constraintEqualToConstant:48].active = YES;

    [row addArrangedSubview:titleStack];
    [row addArrangedSubview:spacer];
    [row addArrangedSubview:self.statusLabel];
    [row addArrangedSubview:saveButton];
    [row addArrangedSubview:helpButton];
    [row addArrangedSubview:settingsButton];
    [panel addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
        [row.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-14],
        [row.centerYAnchor constraintEqualToAnchor:panel.centerYAnchor]
    ]];
    return panel;
}

- (PanelView *)buildVacuumPanel {
    PanelView *panel = [self panelWithTitle:@"VACUUM SYSTEM" height:160];
    NSStackView *row = [self horizontalStack];
    row.alignment = NSLayoutAttributeTop;
    row.spacing = 8;

    self.gauge = [[PressureGaugeView alloc] initWithFrame:NSZeroRect];
    self.gauge.translatesAutoresizingMaskIntoConstraints = NO;
    [self.gauge.widthAnchor constraintEqualToConstant:174].active = YES;
    [self.gauge.heightAnchor constraintEqualToConstant:118].active = YES;

    NSStackView *right = [[NSStackView alloc] init];
    right.orientation = NSUserInterfaceLayoutOrientationVertical;
    right.alignment = NSLayoutAttributeLeading;
    right.spacing = 4;
    right.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *switches = [self horizontalStack];
    switches.spacing = 2;
    self.rpSwitch = [[RockerSwitchControl alloc] initWithTitle:@"RP"];
    self.rpSwitch.tag = SEMRockerTagRP;
    self.rpSwitch.target = self;
    self.rpSwitch.action = @selector(rockerChanged:);
    self.dpSwitch = [[RockerSwitchControl alloc] initWithTitle:@"DP"];
    self.dpSwitch.tag = SEMRockerTagDP;
    self.dpSwitch.target = self;
    self.dpSwitch.action = @selector(rockerChanged:);
    self.hvSwitch = [[RockerSwitchControl alloc] initWithTitle:@"HV"];
    self.hvSwitch.ledColor = [Theme accentRed];
    self.hvSwitch.tag = SEMRockerTagHV;
    self.hvSwitch.target = self;
    self.hvSwitch.action = @selector(rockerChanged:);
    [switches addArrangedSubview:self.rpSwitch];
    [switches addArrangedSubview:self.dpSwitch];
    [switches addArrangedSubview:self.hvSwitch];

    NSStackView *buttons = [self horizontalStack];
    buttons.spacing = 5;
    NSButton *evac = [Theme consoleButtonWithTitle:@"EVAC" target:self action:@selector(evacPressed:)];
    NSButton *vent = [Theme consoleButtonWithTitle:@"VENT" target:self action:@selector(ventPressed:)];
    [evac.widthAnchor constraintEqualToConstant:64].active = YES;
    [vent.widthAnchor constraintEqualToConstant:64].active = YES;
    [buttons addArrangedSubview:evac];
    [buttons addArrangedSubview:vent];

    self.unitsControl = [NSSegmentedControl segmentedControlWithLabels:@[@"Pa", @"Torr"]
                                                          trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                target:self
                                                                action:@selector(unitsChanged:)];
    self.unitsControl.controlSize = NSControlSizeSmall;
    self.unitsControl.font = [Theme smallFont];
    self.unitsControl.selectedSegment = 0;
    [self.unitsControl.widthAnchor constraintEqualToConstant:88].active = YES;

    NSStackView *readouts = [self horizontalStack];
    readouts.spacing = 10;
    self.vacuumReadout = [self valueLabel:@"HIGH VAC"];
    self.emissionReadout = [self valueLabel:@"0.0 µA"];
    self.filamentReadout = [self valueLabel:@"FIL 100%"];
    [readouts addArrangedSubview:self.vacuumReadout];
    [readouts addArrangedSubview:self.emissionReadout];
    [readouts addArrangedSubview:self.filamentReadout];

    NSStackView *leds = [self horizontalStack];
    leds.spacing = 10;
    [leds addArrangedSubview:[self ledWithLabel:@"VAC"]];
    [leds addArrangedSubview:[self ledWithLabel:@"HV"]];
    [leds addArrangedSubview:[self ledWithLabel:@"BEAM"]];
    [leds addArrangedSubview:[self ledWithLabel:@"FAULT"]];

    [right addArrangedSubview:switches];
    [right addArrangedSubview:buttons];
    [right addArrangedSubview:self.unitsControl];
    [right addArrangedSubview:readouts];
    [right addArrangedSubview:leds];

    [row addArrangedSubview:self.gauge];
    [row addArrangedSubview:right];
    [panel addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:panel.topAnchor constant:29],
        [row.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-14],
        [row.bottomAnchor constraintLessThanOrEqualToAnchor:panel.bottomAnchor constant:-6]
    ]];
    return panel;
}

- (NSView *)ledWithLabel:(NSString *)text {
    NSStackView *stack = [self horizontalStack];
    stack.spacing = 4;
    LEDIndicatorView *led = [[LEDIndicatorView alloc] initWithFrame:NSZeroRect];
    led.translatesAutoresizingMaskIntoConstraints = NO;
    [led.widthAnchor constraintEqualToConstant:12].active = YES;
    [led.heightAnchor constraintEqualToConstant:12].active = YES;
    NSTextField *label = [self label:text size:7 color:[Theme colorWithHex:0x474238]];
    [stack addArrangedSubview:led];
    [stack addArrangedSubview:label];
    if ([text isEqualToString:@"VAC"]) self.vacuumLED = led;
    else if ([text isEqualToString:@"HV"]) self.hvLED = led;
    else if ([text isEqualToString:@"BEAM"]) self.beamLED = led;
    else if ([text isEqualToString:@"FAULT"]) {
        self.faultLED = led;
        led.color = [Theme accentRed];
    }
    return stack;
}

- (RotaryKnobControl *)knobWithLabel:(NSString *)label
                                 min:(double)min
                                 max:(double)max
                            defValue:(double)def
                                unit:(NSString *)unit
                                 tag:(SEMKnobTag)tag
                            logScale:(BOOL)logScale {
    RotaryKnobControl *knob = [[RotaryKnobControl alloc] initWithLabel:label min:min max:max defaultValue:def unit:unit];
    knob.tag = tag;
    knob.target = self;
    knob.action = @selector(knobChanged:);
    knob.logarithmic = logScale;
    knob.translatesAutoresizingMaskIntoConstraints = NO;
    [knob.widthAnchor constraintEqualToConstant:84].active = YES;
    [knob.heightAnchor constraintEqualToConstant:104].active = YES;
    return knob;
}

- (PanelView *)buildOpticsPanel {
    PanelView *panel = [self panelWithTitle:@"ELECTRON OPTICS" height:254];
    NSStackView *content = [self contentStackInPanel:panel topInset:29];
    content.spacing = 6;

    NSStackView *row1 = [self horizontalStack];
    row1.spacing = 8;
    self.voltageSelector = [[VoltageSelectorView alloc] initWithFrame:NSZeroRect];
    self.voltageSelector.translatesAutoresizingMaskIntoConstraints = NO;
    self.voltageSelector.target = self;
    self.voltageSelector.action = @selector(voltageChanged:);
    [self.voltageSelector.widthAnchor constraintEqualToConstant:300].active = YES;
    [self.voltageSelector.heightAnchor constraintEqualToConstant:38].active = YES;

    self.filamentKnob = [self knobWithLabel:@"FILAMENT" min:0 max:1 defValue:0.62 unit:@"%" tag:SEMKnobTagFilament logScale:NO];
    self.filamentKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f%%", value * 100.0]; };
    self.spotKnob = [self knobWithLabel:@"SPOT" min:0 max:7 defValue:4 unit:@"" tag:SEMKnobTagSpot logScale:NO];
    self.spotKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f", value]; };

    [row1 addArrangedSubview:self.voltageSelector];
    [row1 addArrangedSubview:self.filamentKnob];
    [row1 addArrangedSubview:self.spotKnob];

    NSStackView *row2 = [self horizontalStack];
    row2.spacing = 2;
    self.magnificationKnob = [self knobWithLabel:@"MAGNIFICATION" min:10 max:100000 defValue:1000 unit:@"x" tag:SEMKnobTagMagnification logScale:YES];
    self.magnificationKnob.valueFormatter = ^NSString *(double value) { return [SEMScaleMath formatMagnification:value]; };
    self.focusCoarseKnob = [self knobWithLabel:@"FOCUS COARSE" min:-1 max:1 defValue:0 unit:@"" tag:SEMKnobTagFocusCoarse logScale:NO];
    self.focusCoarseKnob.step = 0.02;
    self.focusCoarseKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.2f", value]; };
    self.focusFineKnob = [self knobWithLabel:@"FOCUS FINE" min:-1 max:1 defValue:0 unit:@"" tag:SEMKnobTagFocusFine logScale:NO];
    self.focusFineKnob.step = 0.002;
    self.focusFineKnob.fineStep = 0.0002;
    self.focusFineKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.3f", value]; };
    self.stigXKnob = [self knobWithLabel:@"STIG X" min:-1 max:1 defValue:0 unit:@"" tag:SEMKnobTagStigX logScale:NO];
    self.stigXKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.2f", value]; };
    self.stigYKnob = [self knobWithLabel:@"STIG Y" min:-1 max:1 defValue:0 unit:@"" tag:SEMKnobTagStigY logScale:NO];
    self.stigYKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.2f", value]; };
    self.workingDistanceKnob = [self knobWithLabel:@"WD" min:8 max:48 defValue:15 unit:@"mm" tag:SEMKnobTagWorkingDistance logScale:NO];
    self.workingDistanceKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.1f mm", value]; };

    [row2 addArrangedSubview:self.magnificationKnob];
    [row2 addArrangedSubview:self.focusCoarseKnob];
    [row2 addArrangedSubview:self.focusFineKnob];
    [row2 addArrangedSubview:self.stigXKnob];
    [row2 addArrangedSubview:self.stigYKnob];
    [row2 addArrangedSubview:self.workingDistanceKnob];

    [content addArrangedSubview:row1];
    [content addArrangedSubview:row2];
    return panel;
}

- (PanelView *)buildStagePanel {
    PanelView *panel = [self panelWithTitle:@"SPECIMEN STAGE" height:144];
    NSStackView *content = [self contentStackInPanel:panel topInset:29];
    content.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    content.alignment = NSLayoutAttributeCenterY;
    content.spacing = 2;

    self.stageXKnob = [self knobWithLabel:@"X" min:0 max:10 defValue:5 unit:@"mm" tag:SEMKnobTagStageX logScale:NO];
    self.stageXKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.2f mm", value]; };
    self.stageYKnob = [self knobWithLabel:@"Y" min:0 max:10 defValue:5 unit:@"mm" tag:SEMKnobTagStageY logScale:NO];
    self.stageYKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.2f mm", value]; };
    self.stageZKnob = [self knobWithLabel:@"Z" min:-1 max:1 defValue:0 unit:@"mm" tag:SEMKnobTagStageZ logScale:NO];
    self.stageZKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.2f mm", value]; };
    self.tiltKnob = [self knobWithLabel:@"TILT" min:-10 max:90 defValue:0 unit:@"°" tag:SEMKnobTagTilt logScale:NO];
    self.tiltKnob.step = 1.0;
    self.tiltKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.1f°", value]; };
    self.rotationKnob = [self knobWithLabel:@"ROTATION" min:0 max:360 defValue:0 unit:@"°" tag:SEMKnobTagRotation logScale:NO];
    self.rotationKnob.step = 1.0;
    self.rotationKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.0f°", value]; };

    [content addArrangedSubview:self.stageXKnob];
    [content addArrangedSubview:self.stageYKnob];
    [content addArrangedSubview:self.stageZKnob];
    [content addArrangedSubview:self.tiltKnob];
    [content addArrangedSubview:self.rotationKnob];

    NSButton *center = [Theme consoleButtonWithTitle:@"CENTER" target:self action:@selector(centerStage:)];
    [center.widthAnchor constraintEqualToConstant:76].active = YES;
    [content addArrangedSubview:center];
    return panel;
}

- (PanelView *)buildDetectorPanel {
    PanelView *panel = [self panelWithTitle:@"DETECTOR / SCAN" height:206];
    NSStackView *row = [self horizontalStack];
    row.alignment = NSLayoutAttributeTop;
    row.spacing = 12;

    NSStackView *knobs = [self horizontalStack];
    knobs.alignment = NSLayoutAttributeTop;
    knobs.spacing = 2;
    self.brightnessKnob = [self knobWithLabel:@"BRIGHTNESS" min:-1 max:1 defValue:0 unit:@"" tag:SEMKnobTagBrightness logScale:NO];
    self.brightnessKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.2f", value]; };
    self.contrastKnob = [self knobWithLabel:@"CONTRAST" min:-1 max:1 defValue:0 unit:@"" tag:SEMKnobTagContrast logScale:NO];
    self.contrastKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%+.2f", value]; };
    self.scanSpeedKnob = [self knobWithLabel:@"SCAN TIME" min:1 max:15 defValue:5 unit:@"s" tag:SEMKnobTagScanSpeed logScale:NO];
    self.scanSpeedKnob.valueFormatter = ^NSString *(double value) { return [NSString stringWithFormat:@"%.1f s", value]; };
    [knobs addArrangedSubview:self.brightnessKnob];
    [knobs addArrangedSubview:self.contrastKnob];
    [knobs addArrangedSubview:self.scanSpeedKnob];

    NSStackView *right = [[NSStackView alloc] init];
    right.orientation = NSUserInterfaceLayoutOrientationVertical;
    right.alignment = NSLayoutAttributeLeading;
    right.spacing = 4;
    right.translatesAutoresizingMaskIntoConstraints = NO;

    self.detectorControl = [NSSegmentedControl segmentedControlWithLabels:@[@"SE", @"BSE"]
                                                             trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                   target:self
                                                                   action:@selector(detectorChanged:)];
    self.detectorControl.controlSize = NSControlSizeSmall;
    self.detectorControl.font = [Theme smallFont];
    self.detectorControl.selectedSegment = 0;
    [self.detectorControl.widthAnchor constraintEqualToConstant:260].active = YES;

    self.scanControl = [NSSegmentedControl segmentedControlWithLabels:@[@"TV", @"SLOW", @"PHOTO"]
                                                         trackingMode:NSSegmentSwitchTrackingSelectOne
                                                               target:self
                                                               action:@selector(scanModeChanged:)];
    self.scanControl.controlSize = NSControlSizeSmall;
    self.scanControl.font = [Theme smallFont];
    self.scanControl.selectedSegment = 0;
    [self.scanControl.widthAnchor constraintEqualToConstant:260].active = YES;

    self.goldSwitch = [[RockerSwitchControl alloc] initWithTitle:@"GOLD COAT"];
    self.goldSwitch.ledColor = [Theme accentAmber];
    self.goldSwitch.tag = SEMRockerTagGold;
    self.goldSwitch.target = self;
    self.goldSwitch.action = @selector(rockerChanged:);
    self.goldSwitch.translatesAutoresizingMaskIntoConstraints = NO;

    self.phosphorControl = [NSSegmentedControl segmentedControlWithLabels:@[@"GREEN", @"AMBER", @"WHITE"]
                                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                                    target:self
                                                                    action:@selector(phosphorChanged:)];
    self.phosphorControl.controlSize = NSControlSizeSmall;
    self.phosphorControl.font = [Theme smallFont];
    self.phosphorControl.selectedSegment = 0;
    [self.phosphorControl.widthAnchor constraintEqualToConstant:260].active = YES;

    NSButton *aiButton = [Theme consoleButtonWithTitle:@"SPECIMEN…" target:self action:@selector(aiPressed:)];
    [aiButton.widthAnchor constraintEqualToConstant:150].active = YES;

    [right addArrangedSubview:self.detectorControl];
    [right addArrangedSubview:self.scanControl];
    [right addArrangedSubview:self.goldSwitch];
    [right addArrangedSubview:self.phosphorControl];
    [right addArrangedSubview:aiButton];

    [row addArrangedSubview:knobs];
    [row addArrangedSubview:right];
    [panel addSubview:row];
    [NSLayoutConstraint activateConstraints:@[
        [row.topAnchor constraintEqualToAnchor:panel.topAnchor constant:29],
        [row.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:14],
        [row.trailingAnchor constraintLessThanOrEqualToAnchor:panel.trailingAnchor constant:-14],
        [row.bottomAnchor constraintLessThanOrEqualToAnchor:panel.bottomAnchor constant:-6]
    ]];
    return panel;
}

#pragma mark - Actions

- (void)knobChanged:(RotaryKnobControl *)sender {
    switch ((SEMKnobTag)sender.tag) {
        case SEMKnobTagFilament: [self.engine setFilamentCurrent:sender.doubleValue]; break;
        case SEMKnobTagSpot: [self.engine setSpotSize:sender.doubleValue]; break;
        case SEMKnobTagMagnification: [self.engine setMagnification:sender.doubleValue]; break;
        case SEMKnobTagFocusCoarse:
        case SEMKnobTagFocusFine: [self.engine setFocus:sender.doubleValue]; break;
        case SEMKnobTagStigX: [self.engine setStigmatorX:sender.doubleValue]; break;
        case SEMKnobTagStigY: [self.engine setStigmatorY:sender.doubleValue]; break;
        case SEMKnobTagWorkingDistance: [self.engine setWorkingDistanceMM:sender.doubleValue]; break;
        case SEMKnobTagStageX: [self.engine setStageX:sender.doubleValue]; break;
        case SEMKnobTagStageY: [self.engine setStageY:sender.doubleValue]; break;
        case SEMKnobTagStageZ: [self.engine setStageZ:sender.doubleValue]; break;
        case SEMKnobTagTilt: [self.engine setTilt:sender.doubleValue]; break;
        case SEMKnobTagRotation: [self.engine setRotation:sender.doubleValue]; break;
        case SEMKnobTagBrightness: [self.engine setBrightness:sender.doubleValue]; break;
        case SEMKnobTagContrast: [self.engine setContrast:sender.doubleValue]; break;
        case SEMKnobTagScanSpeed: [self.engine setScanDuration:sender.doubleValue]; break;
    }
}

- (void)voltageChanged:(VoltageSelectorView *)sender {
    [self.engine setAcceleratingVoltageKV:sender.selectedKV];
}

- (void)rockerChanged:(RockerSwitchControl *)sender {
    switch ((SEMRockerTag)sender.tag) {
        case SEMRockerTagRP: [self.engine setRoughingPumpOn:sender.isOn]; break;
        case SEMRockerTagDP: [self.engine setDiffusionPumpOn:sender.isOn]; break;
        case SEMRockerTagHV: [self.engine setHighVoltageOn:sender.isOn]; break;
        case SEMRockerTagGold: [self.engine setGoldCoated:sender.isOn]; break;
    }
    [self refreshFromEngine];
}

- (void)evacPressed:(id)sender {
    [self.engine evac];
    [self refreshFromEngine];
}

- (void)ventPressed:(id)sender {
    [self.engine vent];
    [self refreshFromEngine];
}

- (void)centerStage:(id)sender {
    [self.engine setStageX:5.0];
    [self.engine setStageY:5.0];
    [self.engine setStageZ:0.0];
    [self.engine setTilt:0.0];
    [self refreshFromEngine];
}

- (void)detectorChanged:(NSSegmentedControl *)sender {
    [self.engine setDetectorMode:(sender.selectedSegment == 1 ? SEMDetectorModeBSE : SEMDetectorModeSE)];
}

- (void)scanModeChanged:(NSSegmentedControl *)sender {
    [self.engine setScanMode:(SEMScanMode)sender.selectedSegment];
}

- (void)phosphorChanged:(NSSegmentedControl *)sender {
    self.phosphorMode = (SEMPhosphorMode)sender.selectedSegment;
    [self.delegate consoleView:self didSelectPhosphorMode:self.phosphorMode];
}

- (void)unitsChanged:(NSSegmentedControl *)sender {
    self.torr = (sender.selectedSegment == 1);
    [self.gauge setTorr:self.torr];
}

- (void)aiPressed:(id)sender { [self.delegate consoleViewDidRequestAI:self]; }
- (void)savePressed:(id)sender { [self.delegate consoleViewDidRequestSave:self]; }
- (void)settingsPressed:(id)sender { [self.delegate consoleViewDidRequestSettings:self]; }
- (void)helpPressed:(id)sender { [self.delegate consoleViewDidRequestHelp:self]; }

#pragma mark - Refresh

- (void)refreshFromEngine {
    SEMPhysicsEngine *e = self.engine;
    if (!e) return;

    self.gauge.pressurePa = e.pressurePa;
    self.gauge.torr = self.torr;

    self.rpSwitch.on = e.roughingPumpOn;
    self.dpSwitch.on = e.diffusionPumpOn;
    self.hvSwitch.on = e.highVoltageOn;
    self.goldSwitch.on = e.goldCoated;
    self.dpSwitch.enabled = (e.pressurePa < 10.0);
    self.hvSwitch.enabled = e.vacuumReady;

    [self.filamentKnob setDoubleValueSilently:e.filamentCurrent];
    [self.spotKnob setDoubleValueSilently:e.spotSize];
    [self.magnificationKnob setDoubleValueSilently:e.magnification];
    [self.focusCoarseKnob setDoubleValueSilently:e.focus];
    [self.focusFineKnob setDoubleValueSilently:e.focus];
    [self.stigXKnob setDoubleValueSilently:e.stigmatorX];
    [self.stigYKnob setDoubleValueSilently:e.stigmatorY];
    [self.workingDistanceKnob setDoubleValueSilently:e.workingDistanceMM];
    [self.stageXKnob setDoubleValueSilently:e.stageX];
    [self.stageYKnob setDoubleValueSilently:e.stageY];
    [self.stageZKnob setDoubleValueSilently:e.stageZ];
    [self.tiltKnob setDoubleValueSilently:e.tilt];
    [self.rotationKnob setDoubleValueSilently:e.rotation];
    [self.brightnessKnob setDoubleValueSilently:e.brightness];
    [self.contrastKnob setDoubleValueSilently:e.contrast];
    [self.scanSpeedKnob setDoubleValueSilently:e.scanDuration];

    self.voltageSelector.selectedKV = e.acceleratingVoltageKV;
    self.detectorControl.selectedSegment = (e.detectorMode == SEMDetectorModeBSE) ? 1 : 0;
    self.scanControl.selectedSegment = e.scanMode;

    self.vacuumReadout.stringValue = SEMVacuumStateName(e.vacuumState);
    self.emissionReadout.stringValue = [NSString stringWithFormat:@"%.1f µA", e.emissionCurrent];
    self.filamentReadout.stringValue = [NSString stringWithFormat:@"FIL %.0f%%", e.filamentLife * 100.0];
    self.statusLabel.stringValue = e.statusMessage;
    self.statusLabel.textColor = e.fault ? [Theme colorWithHex:0x7B211A] : [Theme colorWithHex:0x2E4D31];

    self.vacuumLED.on = e.vacuumReady;
    self.hvLED.on = e.highVoltageOn;
    self.beamLED.on = e.beamOn;
    self.faultLED.on = e.fault;
}

@end
