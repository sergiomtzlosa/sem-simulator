#import "MainWindowController.h"
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <math.h>
#import "SEMPhysicsEngine.h"
#import "SEMSpecimen.h"
#import "SEMScaleMath.h"
#import "Theme.h"
#import "ConsoleView.h"
#import "AISampleDrawer.h"
#import "AISampleManager.h"
#import "MetalCRTView.h"
#import "AppDelegate.h"
#import "SettingsWindowController.h"
#import "HelpWindowController.h"
#import "LEDIndicatorView.h"
#import "SEMControlServer.h"
#import "SavedSpecimenStore.h"
#import "SpecimenLibrary.h"

static NSString *SEMSpecimenFileBaseName(NSString *name) {
    NSString *base = name.length > 0 ? name : @"Specimen";
    NSCharacterSet *invalid = [NSCharacterSet characterSetWithCharactersInString:@"/:\\?%*|\"<>"];
    base = [[base componentsSeparatedByCharactersInSet:invalid] componentsJoinedByString:@"-"];
    base = [base stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (base.length > 80) base = [base substringToIndex:80];
    return base.length > 0 ? base : @"Specimen";
}

@interface MainWindowController () <ConsoleViewDelegate, AISampleDrawerDelegate, SEMControlServerDelegate>
@property (nonatomic, strong) SEMPhysicsEngine *engine;
@property (nonatomic, strong) ConsoleView *consoleView;
@property (nonatomic, strong) MetalCRTView *crtView;
@property (nonatomic, strong) AISampleDrawer *aiDrawer;
@property (nonatomic, strong) NSView *drawerContainer;
@property (nonatomic, strong) NSLayoutConstraint *drawerHeightConstraint;
@property (nonatomic, strong) AISampleManager *aiManager;
@property (nonatomic, strong) SavedSpecimenStore *specimenStore;
@property (nonatomic, strong, nullable) SEMControlServer *controlServer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, strong) LEDIndicatorView *crtPowerLED;
@property (nonatomic, strong) NSTextField *crtStatusLabel;
@property (nonatomic, strong) NSTextField *crtLiveLabel;
@property (nonatomic, strong, nullable) SEMSpecimen *pendingSpecimen;
@property (nonatomic, copy, nullable) void (^pendingLoadCompletion)(BOOL loaded, NSError * _Nullable error);
@property (nonatomic, assign) CFTimeInterval lastTick;
@property (nonatomic, assign) NSUInteger frameCounter;
@property (nonatomic, assign) NSUInteger selfTestAttempts;
@property (nonatomic, assign) BOOL autoImagingStatusActive;
- (void)updateCRTLiveInfo;
- (void)updateAutoImagingStatus;
- (void)loadBuiltInModel:(SpecimenPreset *)preset;
@end

@implementation MainWindowController

- (instancetype)init {
    NSRect contentRect = NSMakeRect(0, 0, 1440, 900);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:contentRect
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SEM Simulator";
    window.minSize = NSMakeSize(1280, 928);
    window.backgroundColor = [Theme consoleBackground];
    window.tabbingMode = NSWindowTabbingModeDisallowed;
    self = [super initWithWindow:window];
    if (self) {
        [self buildInterface];
        [self startSimulation];
    }
    return self;
}

- (void)dealloc {
    [self.timer invalidate];
}

- (void)buildInterface {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = [Theme consoleBackground].CGColor;

    self.engine = [[SEMPhysicsEngine alloc] init];
    self.consoleView = [[ConsoleView alloc] initWithEngine:self.engine];
    self.consoleView.delegate = self;
    self.consoleView.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.consoleView];

    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    self.crtView = [[MetalCRTView alloc] initWithFrame:NSZeroRect device:device engine:self.engine];
    self.crtView.translatesAutoresizingMaskIntoConstraints = NO;
    self.crtView.phosphorMode = SEMPhosphorModeGreen;

    NSView *bezel = [[NSView alloc] initWithFrame:NSZeroRect];
    bezel.wantsLayer = YES;
    bezel.layer.backgroundColor = [Theme colorWithHex:0x12120F].CGColor;
    bezel.layer.cornerRadius = 12.0;
    bezel.layer.borderWidth = 1.0;
    bezel.layer.borderColor = [Theme colorWithHex:0x5B5549].CGColor;
    bezel.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:bezel];
    [bezel addSubview:self.crtView];

    NSView *bottomStrip = [[NSView alloc] initWithFrame:NSZeroRect];
    bottomStrip.translatesAutoresizingMaskIntoConstraints = NO;
    [bezel addSubview:bottomStrip];

    NSTextField *badge = [NSTextField labelWithString:@"SEM SIMULATOR   ·   CRT"];
    badge.font = [Theme condensedFontOfSize:9 weight:NSFontWeightSemibold];
    badge.textColor = [Theme colorWithHex:0x9C9586];
    badge.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomStrip addSubview:badge];

    self.crtPowerLED = [[LEDIndicatorView alloc] initWithFrame:NSZeroRect];
    self.crtPowerLED.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomStrip addSubview:self.crtPowerLED];

    NSTextField *powerLabel = [NSTextField labelWithString:@"BEAM"];
    powerLabel.font = [Theme smallFont];
    powerLabel.textColor = [Theme colorWithHex:0x8F887A];
    powerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [bottomStrip addSubview:powerLabel];

    NSButton *zoomOutButton = [Theme consoleButtonWithTitle:@"−" target:self action:@selector(zoomOut:)];
    zoomOutButton.toolTip = @"Zoom out (pinch, Option-scroll, or Cmd-Minus)";
    zoomOutButton.translatesAutoresizingMaskIntoConstraints = NO;
    [zoomOutButton.widthAnchor constraintEqualToConstant:22].active = YES;
    [zoomOutButton.heightAnchor constraintEqualToConstant:18].active = YES;
    [bottomStrip addSubview:zoomOutButton];

    NSButton *zoomInButton = [Theme consoleButtonWithTitle:@"+" target:self action:@selector(zoomIn:)];
    zoomInButton.toolTip = @"Zoom in (pinch, Option-scroll, or Cmd-Plus)";
    zoomInButton.translatesAutoresizingMaskIntoConstraints = NO;
    [zoomInButton.widthAnchor constraintEqualToConstant:22].active = YES;
    [zoomInButton.heightAnchor constraintEqualToConstant:18].active = YES;
    [bottomStrip addSubview:zoomInButton];

    self.crtLiveLabel = [NSTextField labelWithString:@"—"];
    self.crtLiveLabel.font = [Theme monoFontOfSize:8];
    self.crtLiveLabel.textColor = [Theme colorWithHex:0x8C9A82];
    self.crtLiveLabel.alignment = NSTextAlignmentCenter;
    self.crtLiveLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.crtLiveLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.crtLiveLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow
                                                forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bottomStrip addSubview:self.crtLiveLabel];

    self.crtStatusLabel = [NSTextField labelWithString:@"CHAMBER VENTED"];
    self.crtStatusLabel.font = [Theme monoFontOfSize:8];
    self.crtStatusLabel.textColor = [Theme colorWithHex:0x7F8C75];
    self.crtStatusLabel.alignment = NSTextAlignmentRight;
    self.crtStatusLabel.lineBreakMode = NSLineBreakByTruncatingHead;
    self.crtStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.crtStatusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultHigh
                                                 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [bottomStrip addSubview:self.crtStatusLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.crtView.topAnchor constraintEqualToAnchor:bezel.topAnchor constant:14],
        [self.crtView.leadingAnchor constraintEqualToAnchor:bezel.leadingAnchor constant:14],
        [self.crtView.trailingAnchor constraintEqualToAnchor:bezel.trailingAnchor constant:-14],
        [self.crtView.bottomAnchor constraintEqualToAnchor:bezel.bottomAnchor constant:-40],
        [bottomStrip.leadingAnchor constraintEqualToAnchor:bezel.leadingAnchor constant:18],
        [bottomStrip.trailingAnchor constraintEqualToAnchor:bezel.trailingAnchor constant:-18],
        [bottomStrip.bottomAnchor constraintEqualToAnchor:bezel.bottomAnchor constant:-8],
        [bottomStrip.heightAnchor constraintEqualToConstant:20],
        [badge.leadingAnchor constraintEqualToAnchor:bottomStrip.leadingAnchor],
        [badge.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor],
        [self.crtPowerLED.leadingAnchor constraintEqualToAnchor:badge.trailingAnchor constant:12],
        [self.crtPowerLED.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor],
        [powerLabel.leadingAnchor constraintEqualToAnchor:self.crtPowerLED.trailingAnchor constant:4],
        [powerLabel.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor],
        [zoomOutButton.leadingAnchor constraintEqualToAnchor:powerLabel.trailingAnchor constant:12],
        [zoomOutButton.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor],
        [zoomInButton.leadingAnchor constraintEqualToAnchor:zoomOutButton.trailingAnchor constant:4],
        [zoomInButton.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor],
        [self.crtLiveLabel.leadingAnchor constraintEqualToAnchor:zoomInButton.trailingAnchor constant:12],
        [self.crtLiveLabel.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor],
        [self.crtLiveLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.crtStatusLabel.leadingAnchor constant:-10],
        [self.crtStatusLabel.trailingAnchor constraintEqualToAnchor:bottomStrip.trailingAnchor],
        [self.crtStatusLabel.centerYAnchor constraintEqualToAnchor:bottomStrip.centerYAnchor]
    ]];

    self.drawerContainer = [[NSView alloc] initWithFrame:NSZeroRect];
    self.drawerContainer.wantsLayer = YES;
    self.drawerContainer.layer.masksToBounds = YES;
    self.drawerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    [root addSubview:self.drawerContainer];

    self.aiDrawer = [[AISampleDrawer alloc] initWithFrame:NSZeroRect];
    self.aiDrawer.delegate = self;
    self.aiDrawer.translatesAutoresizingMaskIntoConstraints = NO;
    [self.drawerContainer addSubview:self.aiDrawer];

    self.drawerHeightConstraint = [self.drawerContainer.heightAnchor constraintEqualToConstant:260.0];
    [NSLayoutConstraint activateConstraints:@[
        [self.consoleView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:10],
        [self.consoleView.topAnchor constraintEqualToAnchor:root.topAnchor constant:10],
        [self.consoleView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-10],
        [self.consoleView.widthAnchor constraintEqualToConstant:600],

        [bezel.topAnchor constraintEqualToAnchor:root.topAnchor constant:10],
        [bezel.leadingAnchor constraintEqualToAnchor:self.consoleView.trailingAnchor constant:12],
        [bezel.trailingAnchor constraintEqualToAnchor:root.trailingAnchor constant:-10],
        [bezel.bottomAnchor constraintEqualToAnchor:self.drawerContainer.topAnchor constant:-8],
        [bezel.heightAnchor constraintGreaterThanOrEqualToConstant:300],

        [self.drawerContainer.leadingAnchor constraintEqualToAnchor:bezel.leadingAnchor],
        [self.drawerContainer.trailingAnchor constraintEqualToAnchor:bezel.trailingAnchor],
        [self.drawerContainer.bottomAnchor constraintEqualToAnchor:root.bottomAnchor constant:-10],
        self.drawerHeightConstraint,

        [self.aiDrawer.topAnchor constraintEqualToAnchor:self.drawerContainer.topAnchor],
        [self.aiDrawer.leadingAnchor constraintEqualToAnchor:self.drawerContainer.leadingAnchor],
        [self.aiDrawer.trailingAnchor constraintEqualToAnchor:self.drawerContainer.trailingAnchor],
        [self.aiDrawer.heightAnchor constraintEqualToConstant:260.0]
    ]];

    self.aiManager = [[AISampleManager alloc] initWithDevice:device];
    self.specimenStore = [SavedSpecimenStore sharedStore];
    [self startControlServer];
    [self generateDefaultSpecimen];

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.crtView.shaderError.length > 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Metal shader compilation failed";
            alert.informativeText = self.crtView.shaderError;
            [alert addButtonWithTitle:@"Continue"];
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        }
    });
}

- (void)startControlServer {
    uint16_t port = 47831;
    NSDictionary<NSString *, NSString *> *environment = NSProcessInfo.processInfo.environment;
    NSString *environmentPort = environment[@"SEM_CONTROL_PORT"];
    if (environmentPort.length > 0) {
        NSInteger value = environmentPort.integerValue;
        if (value > 0 && value <= 65535) port = (uint16_t)value;
    }

    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    NSUInteger portArgument = [arguments indexOfObject:@"--control-port"];
    if (portArgument != NSNotFound && portArgument + 1 < arguments.count) {
        NSInteger value = arguments[portArgument + 1].integerValue;
        if (value > 0 && value <= 65535) port = (uint16_t)value;
    }

    self.controlServer = [[SEMControlServer alloc] initWithDelegate:self];
    NSError *error = nil;
    if (![self.controlServer startOnPort:port error:&error]) {
        NSLog(@"SEM control API unavailable: %@", error.localizedDescription);
        self.controlServer = nil;
        return;
    }

    NSString *authentication = environment[@"SEM_CONTROL_TOKEN"].length > 0 ? @" (bearer token required)" : @"";
    NSLog(@"SEM control API listening on http://127.0.0.1:%u%@", self.controlServer.port, authentication);
}

- (void)generateDefaultSpecimen {
    [self.aiDrawer setBusy:YES];
    [self.aiDrawer setStatusText:@"SYNTHESIZING DEFAULT SPECIMEN…"];
    __weak typeof(self) weakSelf = self;
    [self.aiManager generateSpecimenForPrompt:@"Fractured titanium alloy surface" variation:20240517
                                   completion:^(SEMSpecimen * _Nullable specimen, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        self.aiDrawer.busy = NO;
        if (specimen) {
            [self.aiDrawer setSpecimen:specimen];
            [self.aiDrawer setStatusText:@"DEFAULT SPECIMEN READY - EVAC FOR AUTO HV"];
            self.engine.specimen = specimen;
            self.crtView.specimen = specimen;
            self.crtStatusLabel.stringValue = specimen.name.uppercaseString;
            [self.consoleView refreshFromEngine];
        } else {
            [self.aiDrawer setStatusText:error.localizedDescription ?: @"GENERATION FAILED"];
        }
    }];
}

- (void)startSimulation {
    self.lastTick = CACurrentMediaTime();
    self.timer = [NSTimer timerWithTimeInterval:1.0 / 60.0 target:self selector:@selector(tick:) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)tick:(NSTimer *)timer {
    CFTimeInterval now = CACurrentMediaTime();
    NSTimeInterval dt = MIN(now - self.lastTick, 0.1);
    self.lastTick = now;
    if (dt <= 0) return;

    [self.engine tick:dt];
    [self.crtView drawFrame];

    self.frameCounter++;
    if (self.frameCounter % 3 == 0) {
        [self.consoleView refreshFromEngine];
        self.crtPowerLED.on = self.engine.beamOn;
        self.crtStatusLabel.stringValue = self.engine.statusMessage;
        [self updateCRTLiveInfo];
        [self updateAutoImagingStatus];
    }

    if (self.pendingSpecimen && self.engine.vacuumState == SEMVacuumStateVented) {
        SEMSpecimen *specimen = self.pendingSpecimen;
        void (^completion)(BOOL, NSError *) = self.pendingLoadCompletion;
        self.pendingSpecimen = nil;
        self.pendingLoadCompletion = nil;
        [self applySpecimen:specimen];
        if (completion) completion(YES, nil);
    }
}

- (void)updateCRTLiveInfo {
    SEMPhysicsEngine *engine = self.engine;
    NSString *detector = engine.detectorMode == SEMDetectorModeBSE ? @"BSE" : @"SE";
    NSString *scan = [self scanModeName:engine.scanMode];
    self.crtLiveLabel.stringValue = [NSString stringWithFormat:@"%@  ·  %ld kV  ·  %@ / %@  ·  WD %.1f mm  ·  %@",
                                     [SEMScaleMath formatMagnification:engine.magnification],
                                     (long)engine.acceleratingVoltageKV,
                                     detector,
                                     scan,
                                     engine.workingDistanceMM,
                                     [SEMScaleMath formatPressurePa:engine.pressurePa torr:NO]];
}

- (void)applySpecimen:(SEMSpecimen *)specimen {
    self.engine.specimen = specimen;
    self.crtView.specimen = specimen;
    [self.aiDrawer setSpecimen:specimen];
    [self.aiDrawer setStatusText:@"SPECIMEN LOADED - AUTO EVACUATING…"];
    [self.consoleView refreshFromEngine];
    [self updateCRTLiveInfo];

    // One action loads and images a model: vent (handled by loadSpecimen),
    // evacuate, then let the engine turn HV on as soon as the vacuum is ready.
    [self.engine evac];
    self.autoImagingStatusActive = YES;
}

- (void)updateAutoImagingStatus {
    if (!self.autoImagingStatusActive) return;

    SEMPhysicsEngine *engine = self.engine;
    if (engine.fault) {
        [self.aiDrawer setStatusText:@"VACUUM FAULT - RESET IN SETTINGS"];
        self.autoImagingStatusActive = NO;
        return;
    }
    if (engine.highVoltageOn) {
        [self.aiDrawer setStatusText:@"HIGH VACUUM READY - HV ON - IMAGING"];
        self.autoImagingStatusActive = NO;
        return;
    }
    if (engine.vacuumState == SEMVacuumStateVented || engine.vacuumState == SEMVacuumStateVenting) {
        self.autoImagingStatusActive = NO;
        return;
    }
    if (engine.vacuumState == SEMVacuumStateDPWarmup) {
        [self.aiDrawer setStatusText:[NSString stringWithFormat:@"AUTO EVAC - DIFFUSION PUMP WARMING %.0fs",
                                      ceil(engine.dpWarmupRemaining)]];
    } else if (engine.vacuumState == SEMVacuumStateHighVacuum) {
        [self.aiDrawer setStatusText:[NSString stringWithFormat:@"AUTO EVAC - PUMPING DOWN %.2g Pa",
                                      engine.pressurePa]];
    } else {
        [self.aiDrawer setStatusText:[NSString stringWithFormat:@"AUTO EVAC - ROUGH VACUUM %.2g Pa",
                                      engine.pressurePa]];
    }
}

- (void)loadSpecimen:(SEMSpecimen *)specimen {
    [self loadSpecimen:specimen completion:nil];
}

- (void)loadSpecimen:(SEMSpecimen *)specimen completion:(void (^)(BOOL loaded, NSError * _Nullable error))completion {
    if (!specimen) {
        if (completion) completion(NO, SEMControlMakeError(SEMControlErrorInvalidRequest, @"No specimen supplied."));
        return;
    }

    if (self.pendingLoadCompletion) {
        void (^previous)(BOOL, NSError *) = self.pendingLoadCompletion;
        self.pendingLoadCompletion = nil;
        self.pendingSpecimen = nil;
        previous(NO, SEMControlMakeError(SEMControlErrorBusy, @"Superseded by a newer specimen load."));
    }

    if (self.engine.highVoltageOn) {
        [self.engine setHighVoltageOn:NO];
    }

    if (self.engine.vacuumState == SEMVacuumStateVented) {
        [self applySpecimen:specimen];
        if (completion) completion(YES, nil);
        return;
    }

    self.pendingSpecimen = specimen;
    self.pendingLoadCompletion = completion;
    [self.engine vent];
    [self.aiDrawer setStatusText:@"VENTING CHAMBER FOR SPECIMEN LOAD…"];

    if (completion) {
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(60.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self.pendingSpecimen != specimen) return;
            void (^pending)(BOOL, NSError *) = self.pendingLoadCompletion;
            self.pendingSpecimen = nil;
            self.pendingLoadCompletion = nil;
            if (pending) {
                pending(NO, SEMControlMakeError(SEMControlErrorTimeout, @"Timed out waiting for the chamber to vent."));
            }
        });
    }
}

- (IBAction)toggleAIDrawer:(nullable id)sender {
    BOOL opening = self.drawerHeightConstraint.constant < 1.0;
    if (opening) self.drawerContainer.hidden = NO;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        context.duration = 0.22;
        context.allowsImplicitAnimation = YES;
        self.drawerHeightConstraint.animator.constant = opening ? 260.0 : 0.0;
    } completionHandler:^{
        if (!opening) self.drawerContainer.hidden = YES;
    }];
}

- (IBAction)zoomIn:(id)sender {
    [self.crtView zoomByFactor:1.25];
    [self.consoleView refreshFromEngine];
    [self updateCRTLiveInfo];
}

- (IBAction)zoomOut:(id)sender {
    [self.crtView zoomByFactor:0.8];
    [self.consoleView refreshFromEngine];
    [self updateCRTLiveInfo];
}

- (IBAction)resetZoom:(id)sender {
    [self.crtView resetMagnification];
    [self.consoleView refreshFromEngine];
    [self updateCRTLiveInfo];
}

- (void)loadOfflineSpecimen:(SpecimenPreset *)preset {
    [self loadBuiltInModel:preset];
}

- (void)loadBuiltInModel:(SpecimenPreset *)preset {
    if (!preset) return;
    if (self.aiDrawer.busy) {
        NSBeep();
        return;
    }

    BOOL savedModel = [preset.category isEqualToString:@"SAVED"];
    [self.aiDrawer setBusy:YES];
    [self.aiDrawer setStatusText:[NSString stringWithFormat:@"%@: SYNTHESIZING %@…",
                                  savedModel ? @"SAVED MODEL" : @"BUILT-IN",
                                  preset.name.uppercaseString]];
    __weak typeof(self) weakSelf = self;
    [self.aiManager generateSpecimenForPreset:preset
                                   completion:^(SEMSpecimen * _Nullable specimen, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (!specimen) {
            self.aiDrawer.busy = NO;
            [self.aiDrawer setStatusText:error.localizedDescription ?: @"OFFLINE GENERATION FAILED"];
            return;
        }

        [self.aiDrawer setSpecimen:specimen];
        [self.aiDrawer setStatusText:@"OFFLINE MODEL READY - LOADING INTO CHAMBER…"];
        [self loadSpecimen:specimen completion:^(BOOL loaded, NSError * _Nullable loadError) {
            self.aiDrawer.busy = NO;
            if (loaded) {
                [self.aiDrawer setStatusText:[NSString stringWithFormat:@"LOADED OFFLINE: %@", specimen.name.uppercaseString]];
            } else {
                [self.aiDrawer setStatusText:loadError.localizedDescription ?: @"LOAD FAILED"];
            }
        }];
    }];
}

#pragma mark - ConsoleViewDelegate

- (void)consoleViewDidRequestAI:(id)consoleView {
    [self toggleAIDrawer:nil];
}

- (void)consoleViewDidRequestSave:(id)consoleView {
    [self saveMicrograph:consoleView];
}

- (void)consoleViewDidRequestSettings:(id)consoleView {
    [(AppDelegate *)NSApp.delegate showSettings:consoleView];
}

- (void)consoleViewDidRequestHelp:(id)consoleView {
    [(AppDelegate *)NSApp.delegate showHelp:consoleView];
}

- (void)consoleView:(id)consoleView didSelectPhosphorMode:(SEMPhosphorMode)mode {
    self.crtView.phosphorMode = mode;
}

#pragma mark - AISampleDrawerDelegate

- (void)aiDrawerDidRequestGenerate:(NSString *)prompt variation:(NSUInteger)variation {
    if (self.aiDrawer.busy) {
        NSBeep();
        return;
    }

    [self.aiDrawer setBusy:YES];
    [self.aiDrawer setStatusText:@"OPENCODE: GENERATING SPECIMEN RECIPE…"];
    __weak typeof(self) weakSelf = self;
    [self.aiManager generateSpecimenUsingOpenCodeForPrompt:prompt variation:variation
                                               completion:^(SEMSpecimen * _Nullable specimen, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (!specimen) {
            self.aiDrawer.busy = NO;
            [self.aiDrawer setStatusText:error.localizedDescription ?: @"GENERATION FAILED"];
            return;
        }

        NSString *fallbackNote = self.aiManager.lastGenerationNote;
        [self.aiDrawer setSpecimen:specimen];
        if (fallbackNote.length > 0) {
            [self.aiDrawer setStatusText:[NSString stringWithFormat:@"%@ - LOADING INTO CHAMBER…", fallbackNote]];
        } else {
            [self.aiDrawer setStatusText:@"RECIPE READY - LOADING INTO CHAMBER…"];
        }
        [self loadSpecimen:specimen completion:^(BOOL loaded, NSError * _Nullable loadError) {
            self.aiDrawer.busy = NO;
            if (loaded) {
                if (fallbackNote.length > 0) {
                    [self.aiDrawer setStatusText:[NSString stringWithFormat:@"%@ - LOADED %@",
                                                  fallbackNote, specimen.name.uppercaseString]];
                } else {
                    [self.aiDrawer setStatusText:[NSString stringWithFormat:@"LOADED: %@", specimen.name.uppercaseString]];
                }
            } else {
                [self.aiDrawer setStatusText:loadError.localizedDescription ?: @"LOAD FAILED"];
            }
        }];
    }];
}

- (void)aiDrawerDidRequestLoadBuiltInModel:(SpecimenPreset *)preset {
    [self loadBuiltInModel:preset];
}

- (void)aiDrawerDidRequestSaveSpecimen:(id)drawer {
    [self saveSpecimen:drawer];
}

- (void)aiDrawerDidRequestLoadSpecimenFile:(id)drawer {
    [self loadSpecimenFromFile:drawer];
}

- (void)aiDrawerDidRequestSettings:(id)drawer {
    [(AppDelegate *)NSApp.delegate showSettings:drawer];
}

#pragma mark - Saved specimens

- (IBAction)saveSpecimen:(id)sender {
    if (self.aiDrawer.busy) {
        [self.aiDrawer setStatusText:@"WAIT FOR THE CURRENT GENERATION TO FINISH"];
        NSBeep();
        return;
    }

    SEMSpecimen *specimen = self.engine.specimen;
    if (!specimen) {
        [self.aiDrawer setStatusText:@"Generate or load a specimen before saving."];
        NSBeep();
        return;
    }

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.title = @"Save Specimen";
    panel.message = @"Save the specimen recipe, metadata, and preview image. A preview PNG is written next to the specimen file.";
    panel.nameFieldStringValue = [[SEMSpecimenFileBaseName(specimen.name)
                                   stringByAppendingPathExtension:SEMSpecimenFileExtension] copy];
    panel.canCreateDirectories = YES;
    UTType *type = [UTType typeWithFilenameExtension:SEMSpecimenFileExtension];
    if (type) panel.allowedContentTypes = @[type];

    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL == nil) return;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        NSError *error = nil;
        if (![self saveCurrentSpecimenToURL:panel.URL error:&error]) {
            [self presentSpecimenFileError:error title:@"Could Not Save Specimen"];
        }
    }];
}

- (BOOL)saveCurrentSpecimenToURL:(NSURL *)url error:(NSError **)error {
    SEMSpecimen *specimen = self.engine.specimen;
    if (!specimen) {
        if (error) {
            *error = [NSError errorWithDomain:@"SEM.SpecimenFile"
                                         code:30
                                     userInfo:@{NSLocalizedDescriptionKey: @"There is no specimen to save."}];
        }
        return NO;
    }

    SavedSpecimenStore *store = self.specimenStore ?: [SavedSpecimenStore sharedStore];
    if (url.pathExtension.length == 0) {
        url = [url URLByAppendingPathExtension:SEMSpecimenFileExtension];
    }
    if (![store saveSpecimen:specimen sourcePrompt:specimen.sourcePrompt toURL:url error:error]) {
        return NO;
    }

    [self.aiDrawer reloadOfflineModels];
    [self.aiDrawer setStatusText:[NSString stringWithFormat:@"SAVED: %@ + PREVIEW - ADDED TO OFFLINE MODELS",
                                  specimen.name.uppercaseString]];
    return YES;
}

- (IBAction)loadSpecimenFromFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"Load Specimen File";
    panel.message = @"Choose a saved .semspecimen file. It will be loaded and added to the offline list.";
    panel.prompt = @"Load";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    UTType *type = [UTType typeWithFilenameExtension:SEMSpecimenFileExtension];
    if (type) panel.allowedContentTypes = @[type];

    __weak typeof(self) weakSelf = self;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || panel.URL == nil) return;
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self loadSpecimenFromFileURL:panel.URL];
    }];
}

- (void)loadSpecimenFromFileURL:(NSURL *)url {
    if (self.aiDrawer.busy) {
        [self.aiDrawer setStatusText:@"WAIT FOR THE CURRENT GENERATION TO FINISH"];
        NSBeep();
        return;
    }

    SavedSpecimenStore *store = self.specimenStore ?: [SavedSpecimenStore sharedStore];
    NSError *error = nil;
    SpecimenPreset *preset = [store importSpecimenFromURL:url error:&error];
    if (!preset) {
        [self presentSpecimenFileError:error title:@"Could Not Load Specimen"];
        return;
    }

    [self.aiDrawer reloadOfflineModels];
    [self.aiDrawer setStatusText:[NSString stringWithFormat:@"IMPORTED: %@ - LOADING…",
                                  preset.name.uppercaseString]];
    [self loadOfflineSpecimen:preset];
}

- (void)presentSpecimenFileError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: @"Unknown specimen file error.";
    [alert addButtonWithTitle:@"OK"];
    if (self.window) {
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

#pragma mark - SEMControlServerDelegate

- (NSDictionary<NSString *, id> *)statusForControlServer:(SEMControlServer *)server {
    SEMPhysicsEngine *engine = self.engine;
    NSMutableDictionary<NSString *, id> *status = [NSMutableDictionary dictionary];
    status[@"ok"] = @YES;
    status[@"app"] = @"SEM Simulator";
    status[@"controlApi"] = @1;
    status[@"vacuum"] = SEMVacuumStateName(engine.vacuumState);
    status[@"vacuumStateID"] = @(engine.vacuumState);
    status[@"pressurePa"] = @(engine.pressurePa);
    status[@"pressureTorr"] = @(engine.pressurePa * 0.00750061683);
    status[@"vacuumReady"] = @(engine.vacuumReady);
    status[@"roughingPumpOn"] = @(engine.roughingPumpOn);
    status[@"diffusionPumpOn"] = @(engine.diffusionPumpOn);
    status[@"highVoltageOn"] = @(engine.highVoltageOn);
    status[@"beamOn"] = @(engine.beamOn);
    status[@"fault"] = @(engine.fault);
    status[@"acceleratingVoltageKV"] = @(engine.acceleratingVoltageKV);
    status[@"magnification"] = @(engine.magnification);
    status[@"workingDistanceMM"] = @(engine.workingDistanceMM);
    status[@"spotSize"] = @(engine.spotSize);
    status[@"detector"] = engine.detectorMode == SEMDetectorModeBSE ? @"BSE" : @"SE";
    status[@"scanMode"] = [self scanModeName:engine.scanMode];
    status[@"goldCoated"] = @(engine.goldCoated);
    status[@"charge"] = @(engine.charge);
    status[@"statusMessage"] = engine.statusMessage ?: @"";
    status[@"specimen"] = engine.specimen ? [self specimenDictionary:engine.specimen] : [NSNull null];
    return status;
}

- (NSDictionary<NSString *, id> *)specimenDictionary:(SEMSpecimen *)specimen {
    return @{
        @"name": specimen.name ?: @"Untitled specimen",
        @"template": specimen.templateName ?: @"",
        @"conductive": @(specimen.conductive),
        @"coatingRecommended": @(specimen.coatingRecommended),
        @"meanZ": @(specimen.meanZ),
        @"scaleMicrometers": @(specimen.scaleMicrometers),
        @"seed": @(specimen.seed)
    };
}

- (NSString *)scanModeName:(SEMScanMode)mode {
    switch (mode) {
        case SEMScanModeTV: return @"TV";
        case SEMScanModeSlow: return @"SLOW";
        case SEMScanModePhoto: return @"PHOTO";
    }
    return @"TV";
}

- (void)controlServer:(SEMControlServer *)server
    setSampleWithPrompt:(NSString *)prompt
              variation:(NSUInteger)variation
                   load:(BOOL)load
               goldCoat:(BOOL)goldCoat
             completion:(void (^)(NSDictionary<NSString *, id> * _Nullable result,
                                  NSError * _Nullable error))completion {
    if (self.aiDrawer.busy) {
        if (completion) completion(nil, SEMControlMakeError(SEMControlErrorBusy, @"The specimen generator is already running."));
        return;
    }

    [self.aiDrawer setBusy:YES];
    [self.aiDrawer setStatusText:@"SYNTHESIZING SPECIMEN…"];
    __weak typeof(self) weakSelf = self;
    [self.aiManager generateSpecimenForPrompt:prompt
                                    variation:variation
                                   completion:^(SEMSpecimen * _Nullable specimen, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            if (completion) completion(nil, error ?: SEMControlMakeError(SEMControlErrorInternal, @"SEM Simulator closed."));
            return;
        }

        self.aiDrawer.busy = NO;
        if (!specimen) {
            [self.aiDrawer setStatusText:error.localizedDescription ?: @"GENERATION FAILED"];
            if (completion) completion(nil, error ?: SEMControlMakeError(SEMControlErrorInternal, @"Specimen generation failed."));
            return;
        }

        [self.aiDrawer setSpecimen:specimen];
        if (goldCoat) {
            [self.engine setGoldCoated:YES];
            [self.consoleView refreshFromEngine];
        }

        if (!load) {
            [self.aiDrawer setStatusText:@"SPECIMEN READY - LOAD SKIPPED"];
            if (completion) {
                completion(@{
                    @"ok": @YES,
                    @"loaded": @NO,
                    @"specimen": [self specimenDictionary:specimen],
                    @"status": [self statusForControlServer:server]
                }, nil);
            }
            return;
        }

        [self loadSpecimen:specimen completion:^(BOOL loaded, NSError * _Nullable loadError) {
            if (!loaded) {
                if (completion) completion(nil, loadError ?: SEMControlMakeError(SEMControlErrorInternal, @"Could not load specimen."));
                return;
            }
            if (completion) {
                completion(@{
                    @"ok": @YES,
                    @"loaded": @YES,
                    @"specimen": [self specimenDictionary:specimen],
                    @"status": [self statusForControlServer:server]
                }, nil);
            }
        }];
    }];
}

- (BOOL)controlServer:(SEMControlServer *)server performVacuumAction:(NSString *)action error:(NSError **)error {
    if ([action isEqualToString:@"evac"]) {
        if (self.pendingSpecimen) {
            if (error) *error = SEMControlMakeError(SEMControlErrorBusy, @"Wait for the specimen load to finish before evacuating.");
            return NO;
        }
        if (self.engine.fault) {
            if (error) *error = SEMControlMakeError(SEMControlErrorInterlock, @"Vacuum fault active. Reset the fault before evacuating.");
            return NO;
        }
        [self.engine evac];
        [self.consoleView refreshFromEngine];
        return YES;
    }

    if ([action isEqualToString:@"vent"]) {
        [self.engine vent];
        [self.consoleView refreshFromEngine];
        return YES;
    }

    if ([action isEqualToString:@"reset_fault"]) {
        [self.engine resetFault];
        [self.consoleView refreshFromEngine];
        return YES;
    }

    if (error) *error = SEMControlMakeError(SEMControlErrorInvalidRequest, @"Unknown vacuum action. Use evac, vent, or reset_fault.");
    return NO;
}

- (BOOL)controlServer:(SEMControlServer *)server setHighVoltage:(BOOL)on error:(NSError **)error {
    if (on && !self.engine.vacuumReady) {
        if (error) {
            *error = SEMControlMakeError(SEMControlErrorInterlock,
                                         self.engine.fault ? @"HV interlock: vacuum fault active." : @"HV interlock: vacuum is not ready. Evacuate the chamber first.");
        }
        return NO;
    }

    if (on && self.engine.filamentLife <= 0.001) {
        if (error) *error = SEMControlMakeError(SEMControlErrorInterlock, @"HV interlock: filament is open.");
        return NO;
    }

    [self.engine setHighVoltageOn:on];
    [self.consoleView refreshFromEngine];
    if (on && !self.engine.highVoltageOn) {
        if (error) *error = SEMControlMakeError(SEMControlErrorInterlock, self.engine.statusMessage ?: @"HV interlock prevented high voltage.");
        return NO;
    }
    return YES;
}

- (BOOL)controlServer:(SEMControlServer *)server setGoldCoated:(BOOL)coated error:(NSError **)error {
    [self.engine setGoldCoated:coated];
    [self.consoleView refreshFromEngine];
    return YES;
}

#pragma mark - Save

- (IBAction)saveMicrograph:(id)sender {
    NSImage *image = [self.crtView currentFrameImage];
    if (!image) {
        NSBeep();
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypePNG];
    panel.nameFieldStringValue = @"SEM-Micrograph.png";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || !panel.URL) return;
        NSData *tiff = image.TIFFRepresentation;
        NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        NSError *error = nil;
        if (![png writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Could not save micrograph";
            alert.informativeText = error.localizedDescription ?: @"Unknown error";
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        }
    }];
}

#pragma mark - Self test

- (BOOL)writePNGImage:(NSImage *)image toPath:(NSString *)path {
    if (!image) return NO;
    NSData *tiff = image.TIFFRepresentation;
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData:tiff];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES];
}

- (BOOL)captureWindow:(NSWindow *)window toPath:(NSString *)path {
    NSView *content = window.contentView;
    if (!content) return NO;
    [content layoutSubtreeIfNeeded];
    [window displayIfNeeded];
    NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
    if (!rep) return NO;
    [content cacheDisplayInRect:content.bounds toBitmapImageRep:rep];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    return [png writeToFile:path atomically:YES];
}

- (void)runSelfTestSavingToDirectory:(NSString *)directory {
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];

    if (!self.crtView.specimen) {
        self.selfTestAttempts++;
        if (self.selfTestAttempts > 40) {
            fprintf(stderr, "SELFTEST: no specimen generated\n");
            [NSApp terminate:nil];
            return;
        }
        __weak typeof(self) weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf runSelfTestSavingToDirectory:directory];
        });
        return;
    }

    [self.engine evac];
    for (int i = 0; i < 2600; i++) {
        [self.engine tick:0.05];
    }
    [self.engine setHighVoltageOn:YES];
    [self.engine tick:0.05];
    [self.consoleView refreshFromEngine];
    [self.crtView drawFrame];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        [self.crtView drawFrame];

        NSString *crtPath = [directory stringByAppendingPathComponent:@"crt.png"];
        NSString *uiPath = [directory stringByAppendingPathComponent:@"window.png"];
        NSString *settingsPath = [directory stringByAppendingPathComponent:@"settings.png"];
        NSString *helpPath = [directory stringByAppendingPathComponent:@"help.png"];
        [self.window makeFirstResponder:nil];
        BOOL crtOK = [self writePNGImage:[self.crtView currentFrameImage] toPath:crtPath];
        BOOL uiOK = [self captureWindow:self.window toPath:uiPath];

        AppDelegate *delegate = (AppDelegate *)NSApp.delegate;
        [NSApp activateIgnoringOtherApps:YES];
        [delegate showSettings:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BOOL settingsOK = [self captureWindow:delegate.settingsWindowController.window toPath:settingsPath];
            [delegate showHelp:nil];
            BOOL helpOK = [self captureWindow:delegate.helpWindowController.window toPath:helpPath];

            fprintf(stdout, "SELFTEST: crt=%s ui=%s settings=%s help=%s vacuum=%s beam=%s\n",
                    crtOK ? "ok" : "failed",
                    uiOK ? "ok" : "failed",
                    settingsOK ? "ok" : "failed",
                    helpOK ? "ok" : "failed",
                    SEMVacuumStateName(self.engine.vacuumState).UTF8String,
                    self.engine.beamOn ? "on" : "off");
            fflush(stdout);
            [NSApp terminate:nil];
        });
    });
}

@end
