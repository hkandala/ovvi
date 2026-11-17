// A display that exists only in software, drawn at 2x, 60 Hz, sRGB, made the main display: pictures and films come out
// at 2x whatever screen the Mac has (on a 1x monitor they come out at 1x, and look soft on a Retina or 4K screen).
// record-onboarding.sh films on a 4K one (1920 x 1080 pt, the default). Prints "ready" when it is the main display,
// and ends when the process that started it ends. The display goes with it, and macOS puts the screens back.
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
        int asked[2] = {argc == 3 ? atoi(argv[1]) : 1920, argc == 3 ? atoi(argv[2]) : 1080};
        if ((argc != 1 && argc != 3) || asked[0] < 640 || asked[1] < 480 || asked[0] > 4096 || asked[1] > 4096)
            return fail(@"usage: hidpi-display [<width> <height>]   (in points)");
        unsigned int width = (unsigned)asked[0], height = (unsigned)asked[1];
        CGVirtualDisplayDescriptor *descriptor = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
        if (!descriptor || !NSClassFromString(@"CGVirtualDisplayMode"))
            return fail(@"no CGVirtualDisplay in this macOS");
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
        CGDirectDisplayID made = display.displayID;
        // The main display is the one at (0, 0). Moving only this one is undone: every display moves by its offset.
        CGRect at = CGRectNull;
        for (int i = 0; i < 50 && CGRectIsNull(at); i++) {
            CGRect bounds = CGDisplayBounds(made);
            if (bounds.size.width == width) at = bounds;
            else [NSThread sleepForTimeInterval:0.1];
        }
        if (CGRectIsNull(at)) return fail(@"the display did not come up");
        CGDirectDisplayID online[16];
        uint32_t count = 0;
        CGDisplayConfigRef change;
        CGGetOnlineDisplayList(16, online, &count);
        if (CGBeginDisplayConfiguration(&change) != kCGErrorSuccess) return fail(@"the screens cannot change now");
        for (uint32_t i = 0; i < count; i++) {
            if (CGDisplayMirrorsDisplay(online[i]) != kCGNullDirectDisplay) continue;
            CGRect bounds = CGDisplayBounds(online[i]);
            CGConfigureDisplayOrigin(change, online[i], (int32_t)(bounds.origin.x - at.origin.x),
                                     (int32_t)(bounds.origin.y - at.origin.y));
        }
        // Only while this process runs.
        if (CGCompleteDisplayConfiguration(change, kCGConfigureForAppOnly) != kCGErrorSuccess ||
            CGMainDisplayID() != made)
            return fail(@"the display did not become the main display");
        CGDisplayModeRef mode = CGDisplayCopyDisplayMode(made);
        size_t pixels = CGDisplayModeGetPixelWidth(mode);
        CGDisplayModeRelease(mode);
        if (pixels != width * 2) return fail([NSString stringWithFormat:@"the display runs %zu pixels wide", pixels]);
        printf("ready\n");
        fflush(stdout);
        // Also after a kill -9 of the script: it then has a new parent.
        for (pid_t parent = getppid(); getppid() == parent;) sleep(1);
    }
    return 0;
}
