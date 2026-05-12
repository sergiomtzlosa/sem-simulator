#import "HelpWindowController.h"
#import "Theme.h"

static NSMutableAttributedString *SEMHelpLine(NSString *text,
                                              NSFont *font,
                                              NSColor *color,
                                              CGFloat before,
                                              CGFloat after) {
    NSMutableParagraphStyle *paragraph = [[NSMutableParagraphStyle alloc] init];
    paragraph.paragraphSpacingBefore = before;
    paragraph.paragraphSpacing = after;
    paragraph.lineSpacing = 2.0;
    NSString *line = [text stringByAppendingString:@"\n"];
    return [[NSMutableAttributedString alloc] initWithString:line
                                                  attributes:@{
                                                      NSFontAttributeName: font,
                                                      NSForegroundColorAttributeName: color,
                                                      NSParagraphStyleAttributeName: paragraph
                                                  }];
}

static void SEMAppendHelp(NSMutableAttributedString *target,
                          NSString *text,
                          NSFont *font,
                          NSColor *color,
                          CGFloat before,
                          CGFloat after) {
    [target appendAttributedString:SEMHelpLine(text, font, color, before, after)];
}

@implementation HelpWindowController

- (instancetype)init {
    NSRect rect = NSMakeRect(0, 0, 800, 720);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"SEM Simulator Help";
    window.minSize = NSMakeSize(620, 460);
    window.backgroundColor = [Theme colorWithHex:0x11120F];
    self = [super initWithWindow:window];
    if (self) [self buildInterface];
    return self;
}

- (void)buildInterface {
    NSView *root = self.window.contentView;
    root.wantsLayer = YES;
    root.layer.backgroundColor = [Theme colorWithHex:0x11120F].CGColor;

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:root.bounds];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    scrollView.hasVerticalScroller = YES;
    scrollView.hasHorizontalScroller = NO;
    scrollView.autohidesScrollers = YES;
    scrollView.borderType = NSNoBorder;
    scrollView.drawsBackground = NO;

    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 800, 720)];
    textView.editable = NO;
    textView.selectable = YES;
    textView.richText = YES;
    textView.drawsBackground = YES;
    textView.backgroundColor = [Theme colorWithHex:0x11120F];
    textView.textColor = [Theme colorWithHex:0xC9C2B3];
    textView.textContainerInset = NSMakeSize(30, 24);
    textView.minSize = NSMakeSize(0, 0);
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.autoresizingMask = NSViewWidthSizable;
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(800, CGFLOAT_MAX);
    [textView.textStorage setAttributedString:[self helpContent]];
    scrollView.documentView = textView;

    [root addSubview:scrollView];
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:root.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:root.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:root.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:root.bottomAnchor]
    ]];
}

- (NSAttributedString *)helpContent {
    NSMutableAttributedString *text = [[NSMutableAttributedString alloc] init];

    NSFont *display = [Theme condensedFontOfSize:30 weight:NSFontWeightBold];
    NSFont *section = [Theme condensedFontOfSize:15 weight:NSFontWeightBold];
    NSFont *body = [NSFont systemFontOfSize:12.5];
    NSFont *mono = [Theme monoFontOfSize:11];
    NSFont *bullet = [NSFont systemFontOfSize:12.5];

    NSColor *cream = [Theme colorWithHex:0xE8E0D0];
    NSColor *dim = [Theme colorWithHex:0x9C9586];
    NSColor *green = [Theme colorWithHex:0x8CE39B];
    NSColor *amber = [Theme accentAmber];
    NSColor *bodyColor = [Theme colorWithHex:0xC9C2B3];

    SEMAppendHelp(text, @"SEM SIMULATOR", display, cream, 0, 0);
    SEMAppendHelp(text, @"OPERATING GUIDE", section, amber, 0, 4);
    SEMAppendHelp(text,
                  @"A brand-free scanning electron microscope console simulation. The microscope model and map synthesis run locally; no manufacturer affiliation is implied.",
                  body, dim, 0, 10);

    SEMAppendHelp(text, @"QUICK START", section, green, 14, 4);
    SEMAppendHelp(text, @"1.  Choose a specimen from the Specimen menu, or open the SPECIMEN GENERATOR drawer, describe a specimen, and press GENERATE + LOAD.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"2.  No OpenCode server? Open Settings > OFFLINE MODELS (BUILT-IN + SAVED), select a model, and press LOAD OFFLINE. The built-in catalog is always available without a network connection.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"3.  Loading a model runs the whole vacuum sequence automatically: vent if needed, rough vacuum, diffusion-pump warm-up, high vacuum, then HV on.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"4.  Watch the status line for EVAC: ROUGH VACUUM, DIFFUSION PUMP WARMING, and PUMPING DOWN. HV turns on by itself below 5e-3 Pa.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"5.  Adjust magnification, focus, stigmation, working distance, and stage position.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"6.  Press SAVE (Cmd-S) to export the current CRT frame as a PNG micrograph.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"7.  Press SAVE SPECIMEN in the specimen drawer (Cmd-Shift-S) to keep the recipe and preview, then LOAD FILE… (Cmd-O) to bring a saved specimen back into the offline list.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"8.  Press VENT to stop imaging and return the chamber to atmosphere. Loading another specimen vents automatically.", body, bodyColor, 0, 10);

    SEMAppendHelp(text, @"MOUSE, TRACKPAD, AND KEYBOARD", section, green, 14, 4);
    SEMAppendHelp(text, @"•  Pinch with two fingers over the CRT to zoom in or out. The MAGNIFICATION knob and live readouts follow the eased zoom.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  Option-scroll or Command-scroll over the CRT to zoom smoothly. Zoom input is coalesced and eased at the console refresh rate; the full CRT refreshes each frame instead of updating one region slowly. A two-finger smart zoom returns to 1,000x.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  Cmd-Plus and Cmd-Minus zoom; Cmd-0 resets magnification. The View menu contains the same commands.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  Drag a knob vertically to change it. Hold Shift while dragging for fine adjustment. Double-click a knob to restore its default value.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  The mouse wheel over a knob also adjusts it. Keyboard arrow keys work when a knob has focus.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"VACUUM SYSTEM", section, green, 14, 4);
    SEMAppendHelp(text, @"•  RP: rotary roughing pump. DP: diffusion pump. EVAC runs the complete automatic sequence and turns HV on when high vacuum is reached. VENT returns the chamber to atmosphere.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  The pressure gauge can display Pa or Torr. The VAC, HV, BEAM, and FAULT LEDs show live interlocks.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  HV cannot turn on unless the chamber is at high vacuum and the filament is healthy. Venting or a vacuum fault trips HV off and cancels the automatic sequence.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  If a fault occurs, use Settings > RESET VACUUM FAULT before evacuating again.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"ELECTRON OPTICS", section, green, 14, 4);
    SEMAppendHelp(text, @"•  Voltage selector: 1, 5, 10, 15, 20, or 25 kV. FILAMENT sets emission; SPOT sets probe current and depth of field.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  MAGNIFICATION spans 10x to 100,000x. FOCUS COARSE and FOCUS FINE sharpen the image. STIG X and STIG Y correct astigmatism.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  WD changes working distance. Lower WD generally improves resolution; the live CRT readout shows the current value.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"SPECIMEN STAGE AND DETECTOR", section, green, 14, 4);
    SEMAppendHelp(text, @"•  X, Y, Z, TILT, and ROTATION move the specimen. CENTER restores the stage to its neutral position.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  SE is the secondary-electron detector; BSE is backscattered. TV, SLOW, and PHOTO change scan speed and persistence.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  BRIGHTNESS, CONTRAST, and SCAN TIME shape the image. GREEN, AMBER, and WHITE change the CRT phosphor.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"SPECIMEN GENERATOR", section, green, 14, 4);
    SEMAppendHelp(text, @"Open the drawer with SPECIMEN… or View > Show/Hide Specimen Drawer. Describe the specimen in plain language and press GENERATE + LOAD. VARIATION requests a new texture from the same description.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"The app asks the OpenCode server for a strict JSON recipe containing the template, surface features, material brightness, conductivity, and scale. The server must be running and reachable with the URL and optional password in Settings.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"The height, normal, and Z maps are then synthesized locally from that recipe and loaded into the chamber. Loading vents the chamber first, forces the beam off, then automatically evacuates and turns HV on when high vacuum is reached.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"Choose a MODEL from the dropdown in Settings. AUTO prefers a local Ollama or llama.cpp model, then a free model. REFRESH MODELS reloads the list from the server. Rate-limit, authentication, and model errors appear in the drawer status line.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"After generating or loading a specimen, press SAVE SPECIMEN to store its recipe, metadata, source prompt, seed, and preview image in a .semspecimen file. A matching -preview.png is written next to it. Use LOAD FILE… or Specimen > Load Specimen from File… to import a .semspecimen file; it is loaded and added to the offline list.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"OFFLINE MODELS (BUILT-IN + SAVED)", section, green, 14, 4);
    SEMAppendHelp(text, @"The Specimen menu contains 15 ready-to-use models: pollen, diatom, fractured titanium, microchip traces, volcanic ash, salt crystals, carbon fiber, tissue, bone, quartz sand, rusted steel, sponge spicule, foraminifera, butterfly wing, and house fly.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"To load one offline: 1) open Settings > OFFLINE MODELS (BUILT-IN + SAVED), or use the OFFLINE popup in the SPECIMEN GENERATOR drawer; 2) select a model; 3) press LOAD OFFLINE. The same models are also in the Specimen menu, where choosing one starts the same offline load.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"The app reads the bundled recipe, synthesizes the height, normal, and Z maps locally, vents the chamber, loads the specimen, then automatically evacuates and turns HV on. It never contacts OpenCode, so no server, URL, password, or model download is needed.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"Saved specimens appear below the built-in models in the OFFLINE popup, Settings, and the Specimen menu. Each saved entry embeds its preview, so the thumbnail is visible before loading. The app also keeps a managed copy in ~/Library/Application Support/SEM Simulator/Specimens, so an imported specimen stays in the offline list even if the exported file is moved.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"The automatic sequence takes about 40 seconds from atmosphere to high vacuum; the status line shows each stage. Non-conductive specimens charge under the beam; apply GOLD COAT to suppress charging. Long high-magnification scans leave contamination marks; clear them in Settings.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"OPENCODE INTEGRATION", section, green, 14, 4);
    SEMAppendHelp(text, @"OpenCode can drive the simulator through the MCP bridge in .opencode/sem-mcp.mjs. The default OpenCode server URL is http://127.0.0.1:4096 and the default SEM control API is http://127.0.0.1:47831.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"Authentication is optional. The OpenCode password, when used, is stored in .opencode/password (mode 600). An empty or missing file means no authentication, and a blank password field makes the app send no Authorization header.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"Settings > OPENCODE INTEGRATION has SERVER URL, a MODEL dropdown loaded from the server, an optional password/API-key field, TEST SERVER, REFRESH MODELS, and LOAD PASSWORD FILE. AUTO prefers a local or free chat model.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"Start the server with scripts/opencode-serve.sh. Available MCP tools: sem_set_sample, sem_status, sem_vacuum, and sem_imaging.", body, bodyColor, 0, 2);
    SEMAppendHelp(text, @"Some OpenCode builds generate a server password automatically when none is supplied. In that case, copy the printed password into Settings, or set OPENCODE_PASSWORD before starting the server. The SEM control API itself binds only to loopback.", body, dim, 0, 10);

    SEMAppendHelp(text, @"SAVING, SETTINGS, AND SELF-TEST", section, green, 14, 4);
    SEMAppendHelp(text, @"•  SAVE or Cmd-S exports the current CRT frame as a PNG. The image includes the live telemetry overlay and scale bar.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  Settings contains OpenCode integration, the offline model loader, filament replacement, vacuum-fault reset, and contamination clearing.", bullet, bodyColor, 0, 2);
    SEMAppendHelp(text, @"•  The app supports --selftest, which renders a CRT frame and an AppKit snapshot without screen-recording permission.", bullet, bodyColor, 0, 10);

    SEMAppendHelp(text, @"TROUBLESHOOTING", section, green, 14, 4);
    SEMAppendHelp(text, @"HV will not turn on: confirm HIGH VAC, pressure below 5e-3 Pa, filament life above zero, and no active fault.", mono, dim, 0, 2);
    SEMAppendHelp(text, @"OpenCode cannot connect: launch SEM Simulator first, confirm http://127.0.0.1:47831/health, and run scripts/opencode-serve.sh from the project root.", mono, dim, 0, 2);
    SEMAppendHelp(text, @"Specimen generation fails: press TEST SERVER in Settings, choose a working model from the MODEL dropdown, and press REFRESH MODELS if the list is empty. A free-model rate-limit is reported in the drawer. Built-in models work without OpenCode.", mono, dim, 0, 2);
    SEMAppendHelp(text, @"A saved specimen will not load: choose a .semspecimen file created by SAVE SPECIMEN. The file must contain a valid recipe. A matching -preview.png is optional; the embedded preview is used in the offline list.", mono, dim, 0, 2);
    SEMAppendHelp(text, @"Shader compilation failed: confirm SEMShaders.metal.txt, CRTShaders.metal.txt, and ShaderTypes.h are in the app bundle. Do not rename them to .metal.", mono, dim, 0, 2);

    SEMAppendHelp(text, @"SEM Simulator is an original educational visualization, not a real instrument controller. All specimen maps are synthetic.", body, dim, 14, 0);

    return text;
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self.window center];
}

@end
