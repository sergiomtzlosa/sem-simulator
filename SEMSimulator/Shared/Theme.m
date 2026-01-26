#import "Theme.h"
#import <QuartzCore/QuartzCore.h>

@implementation Theme

+ (NSColor *)colorWithHex:(uint32_t)hex {
    return [NSColor colorWithSRGBRed:((hex >> 16) & 0xFF) / 255.0
                               green:((hex >> 8) & 0xFF) / 255.0
                                blue:(hex & 0xFF) / 255.0
                               alpha:1.0];
}

+ (NSColor *)consoleBackground { return [self colorWithHex:0x161712]; }
+ (NSColor *)panelFace { return [self colorWithHex:0xB7B0A0]; }
+ (NSColor *)panelEdge { return [self colorWithHex:0x6A655B]; }
+ (NSColor *)panelHighlight { return [self colorWithHex:0xD6D0C2]; }
+ (NSColor *)labelColor { return [self colorWithHex:0x2A2822]; }
+ (NSColor *)dimLabelColor { return [self colorWithHex:0x5C574E]; }
+ (NSColor *)accentGreen { return [self colorWithHex:0x6BFF8A]; }
+ (NSColor *)accentAmber { return [self colorWithHex:0xFFB23A]; }
+ (NSColor *)accentRed { return [self colorWithHex:0xFF3A2E]; }
+ (NSColor *)crtGreen { return [NSColor colorWithSRGBRed:0.32 green:1.0 blue:0.46 alpha:1.0]; }
+ (NSColor *)crtAmber { return [NSColor colorWithSRGBRed:1.0 green:0.68 blue:0.18 alpha:1.0]; }
+ (NSColor *)crtWhite { return [NSColor colorWithSRGBRed:0.88 green:0.94 blue:1.0 alpha:1.0]; }

+ (NSFont *)monoFontOfSize:(CGFloat)size {
    return [NSFont fontWithName:@"Menlo" size:size] ?: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightRegular];
}

+ (NSFont *)condensedFontOfSize:(CGFloat)size weight:(NSFontWeight)weight {
    return [NSFont fontWithName:@"HelveticaNeue-CondensedBold" size:size]
        ?: [NSFont systemFontOfSize:size weight:weight];
}

+ (NSFont *)labelFont { return [self condensedFontOfSize:10 weight:NSFontWeightSemibold]; }
+ (NSFont *)smallFont { return [self condensedFontOfSize:9 weight:NSFontWeightMedium]; }
+ (NSFont *)titleFont { return [self condensedFontOfSize:12 weight:NSFontWeightBold]; }
+ (NSFont *)valueFont { return [self monoFontOfSize:11]; }

+ (void)styleLabel:(NSTextField *)label {
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [self labelFont];
    label.textColor = [self labelColor];
}

+ (void)styleValueLabel:(NSTextField *)label {
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [self valueFont];
    label.textColor = [self labelColor];
}

+ (void)stylePopupButton:(NSPopUpButton *)popup {
    // On current macOS releases the system popup bezel can disappear over a
    // dark custom window, leaving black text on the background. A fixed light
    // backing layer keeps the control readable in both active and inactive
    // windows, and the Aqua appearance keeps the menu itself light.
    popup.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
    popup.bezelStyle = NSBezelStyleRounded;
    popup.wantsLayer = YES;
    popup.layer.backgroundColor = [self colorWithHex:0xE7E1D3].CGColor;
    popup.layer.borderColor = [self colorWithHex:0x8F887A].CGColor;
    popup.layer.borderWidth = 1.0;
    popup.layer.cornerRadius = 5.0;
    popup.layer.masksToBounds = YES;
    popup.contentTintColor = [self colorWithHex:0x24221D];
    popup.cell.font = popup.font ?: [NSFont systemFontOfSize:11];
    popup.menu.font = popup.font ?: [NSFont systemFontOfSize:11];
}

+ (NSButton *)consoleButtonWithTitle:(NSString *)title target:(nullable id)target action:(nullable SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.font = [self condensedFontOfSize:10 weight:NSFontWeightSemibold];
    button.bezelColor = [self colorWithHex:0xCFC8B8];
    button.contentTintColor = [self colorWithHex:0x24221D];
    // The dark AI drawer can make the system's inactive bezel disappear. A
    // fixed backing layer keeps the controls legible when the window is not key.
    button.wantsLayer = YES;
    button.layer.backgroundColor = [self colorWithHex:0xCFC8B8].CGColor;
    button.layer.cornerRadius = 5.0;
    button.layer.masksToBounds = YES;
    return button;
}

@end
