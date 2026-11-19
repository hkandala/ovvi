// Gives CI's main display the size the UI tests are tuned to (ci.md, Layout), at 1x, for the login session: the
// runner image of 2026-11-19 (macOS 27.2) came up at 1920 x 1080, where the tests' cards and tab rows are wider.
// Lists the display's modes when none fits.
// Usage: ci-display <width> <height>   (in points)
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc != 3) {
            fprintf(stderr, "usage: ci-display <width> <height>\n");
            return 1;
        }
        size_t width = (size_t)atol(argv[1]), height = (size_t)atol(argv[2]);
        CGDirectDisplayID display = CGMainDisplayID();
        NSDictionary *options = @{(__bridge NSString *)kCGDisplayShowDuplicateLowResolutionModes: @YES};
        NSArray *modes = CFBridgingRelease(CGDisplayCopyAllDisplayModes(display, (__bridge CFDictionaryRef)options));
        CGDisplayModeRef now = CGDisplayCopyDisplayMode(display);
        printf("now %zu x %zu pt, %zu px wide\n", CGDisplayModeGetWidth(now), CGDisplayModeGetHeight(now),
               CGDisplayModeGetPixelWidth(now));
        CGDisplayModeRelease(now);
        for (id item in modes) {
            CGDisplayModeRef mode = (__bridge CGDisplayModeRef)item;
            if (CGDisplayModeGetWidth(mode) != width || CGDisplayModeGetHeight(mode) != height ||
                CGDisplayModeGetPixelWidth(mode) != width)
                continue;
            CGDisplayConfigRef change;
            if (CGBeginDisplayConfiguration(&change) != kCGErrorSuccess ||
                CGConfigureDisplayWithDisplayMode(change, display, mode, NULL) != kCGErrorSuccess ||
                CGCompleteDisplayConfiguration(change, kCGConfigureForSession) != kCGErrorSuccess) {
                fprintf(stderr, "the display did not take %zu x %zu\n", width, height);
                return 1;
            }
            CGRect bounds = CGDisplayBounds(CGMainDisplayID());
            printf("set %.0f x %.0f pt\n", bounds.size.width, bounds.size.height);
            return bounds.size.width == width && bounds.size.height == height ? 0 : 1;
        }
        fprintf(stderr, "no %zu x %zu mode at 1x; the display has:\n", width, height);
        for (id item in modes) {
            CGDisplayModeRef mode = (__bridge CGDisplayModeRef)item;
            fprintf(stderr, "  %zu x %zu pt, %zu x %zu px, %.0f Hz\n", CGDisplayModeGetWidth(mode),
                    CGDisplayModeGetHeight(mode), CGDisplayModeGetPixelWidth(mode), CGDisplayModeGetPixelHeight(mode),
                    CGDisplayModeGetRefreshRate(mode));
        }
        return 1;
    }
}
