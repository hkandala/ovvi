// A display that exists only in software, drawn at 2x, 60 Hz, sRGB, made the main display: pictures and films come out
// at 2x whatever screen the Mac has (on a 1x monitor they come out at 1x, and look soft on a Retina or 4K screen).
// record-onboarding.sh films on a 4K one (1920 x 1080 pt, the default). Prints "ready" when it is the main display,
// and ends when stdin closes; the display goes with the process, and macOS puts the screens back as they were.
// CGVirtualDisplay is private API in CoreGraphics.
// Build: clang -fobjc-arc -framework Foundation -framework CoreGraphics hidpi-display.m -o hidpi-display
// Usage: hidpi-display [<width> <height>]   (in points)
#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

@interface CGVirtualDisplayDescriptor : NSObject
@property(retain, nonatomic) dispatch_queue_t queue;
@property(retain, nonatomic) NSString *name;
@property(nonatomic) CGSize sizeInMillimeters;
@property(nonatomic) unsigned int maxPixelsWide, maxPixelsHigh, serialNum, productID, vendorID;
@property(nonatomic) CGPoint redPrimary, greenPrimary, bluePrimary, whitePoint;
@end
@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(unsigned int)width height:(unsigned int)height refreshRate:(double)rate;
@end
@interface CGVirtualDisplaySettings : NSObject
@property(retain, nonatomic) NSArray *modes;
@property(nonatomic) unsigned int hiDPI;
@end
@interface CGVirtualDisplay : NSObject
@property(readonly, nonatomic) CGDirectDisplayID displayID;
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)descriptor;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)settings;
@end

static int fail(NSString *text) {
    fprintf(stderr, "%s\n", text.UTF8String);
    return 1;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        unsigned int width = argc == 3 ? (unsigned)atoi(argv[1]) : 1920;
        unsigned int height = argc == 3 ? (unsigned)atoi(argv[2]) : 1080;
        if (width < 640 || height < 480) return fail(@"usage: hidpi-display [<width> <height>]");
        CGVirtualDisplayDescriptor *descriptor = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
        if (!descriptor) return fail(@"no CGVirtualDisplay in this macOS");
        descriptor.queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
        descriptor.name = @"Ovvi HiDPI";
        // About 163 pixels per inch, as a 27-inch 4K panel.
        descriptor.sizeInMillimeters = CGSizeMake(width * 0.311, height * 0.311);
        descriptor.maxPixelsWide = width * 2;
        descriptor.maxPixelsHigh = height * 2;
        descriptor.vendorID = 0x0BB1;
        descriptor.productID = 0x4B00;
        descriptor.serialNum = 1;
        descriptor.redPrimary = CGPointMake(0.640, 0.330);
        descriptor.greenPrimary = CGPointMake(0.300, 0.600);
        descriptor.bluePrimary = CGPointMake(0.150, 0.060);
        descriptor.whitePoint = CGPointMake(0.3127, 0.3290);
        CGVirtualDisplay *display = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        if (!display) return fail(@"the display was not made");
        CGVirtualDisplaySettings *settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
        settings.hiDPI = 1;
        // With hiDPI, a mode is in points, drawn at 2x.
        settings.modes = @[[[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:width
                                                                                     height:height
                                                                                refreshRate:60]];
        if (![display applySettings:settings]) return fail(@"the display took no 2x mode");
        CGDirectDisplayID id = display.displayID;
        // The main display is the one at (0, 0). Moving only this one is undone: every display moves by its offset.
        CGRect at = CGRectNull;
        for (int i = 0; i < 50 && CGRectIsNull(at); i++) {
            CGRect bounds = CGDisplayBounds(id);
            if (bounds.size.width == width) at = bounds;
            else [NSThread sleepForTimeInterval:0.1];
        }
        if (CGRectIsNull(at)) return fail(@"the display did not come up");
        CGDirectDisplayID online[16];
        uint32_t count = 0;
        CGDisplayConfigRef change;
        CGGetOnlineDisplayList(16, online, &count);
        CGBeginDisplayConfiguration(&change);
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayMirrorsDisplay(online[i]) != kCGNullDirectDisplay) continue;
            CGRect bounds = CGDisplayBounds(online[i]);
            CGConfigureDisplayOrigin(change, online[i], (int32_t)(bounds.origin.x - at.origin.x),
                                     (int32_t)(bounds.origin.y - at.origin.y));
        }
        // Only while this process runs.
        if (CGCompleteDisplayConfiguration(change, kCGConfigureForAppOnly) != kCGErrorSuccess ||
            CGMainDisplayID() != id)
            return fail(@"the display did not become the main display");
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(id);
        size_t pixels = CGDisplayModeGetPixelWidth(mode);
        CGDisplayModeRelease(mode);
        if (pixels != width * 2) return fail([NSString stringWithFormat:@"the display runs %zu pixels wide", pixels]);
        printf("ready\n");
        fflush(stdout);
        char line[256];
        while (fgets(line, sizeof line, stdin)) {}
    }
    return 0;
}
