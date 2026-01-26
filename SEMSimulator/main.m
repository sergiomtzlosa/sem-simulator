#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"

static AppDelegate *gAppDelegate;

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        gAppDelegate = [[AppDelegate alloc] init];
        app.delegate = gAppDelegate;
        [app run];
    }
    return 0;
}
