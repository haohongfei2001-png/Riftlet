// No Apple Event or keyboard event is sent. Only the caller's existing permission
// is queried, addressing only PIDs returned for the installed browser bundle identifiers.
#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
#import <unistd.h>

static NSDictionary *targetPreflight(NSString *bundle) {
    NSArray *apps = [NSRunningApplication runningApplicationsWithBundleIdentifier:bundle];
    NSMutableArray *results = [NSMutableArray array];
    for (NSRunningApplication *app in apps) {
        pid_t target = app.processIdentifier;
        if (target <= 0 || app.terminated) continue;
        AEAddressDesc address = {typeNull, NULL};
        OSStatus status = AECreateDesc(typeKernelProcessID, &target, sizeof(target), &address);
        if (status == noErr) {
            status = AEDeterminePermissionToAutomateTarget(&address, kAECoreSuite, kAEGetData, false);
            AEDisposeDesc(&address);
        }
        [results addObject:@{@"pid":@(target), @"getPermissionOSStatus":@(status)}];
    }
    return @{@"bundle":bundle, @"runningTargets":results};
}

int main(void) {
    @autoreleasepool {
        NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt:@NO};
        NSDictionary *result = @{
            @"senderPID":@(getpid()), @"parentPID":@(getppid()),
            @"axTrusted":AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options) ? @YES : @NO,
            @"cgPostingPreflight":@(CGPreflightPostEventAccess()),
            @"appleEventGet":@[targetPreflight(@"com.google.Chrome"),targetPreflight(@"com.microsoft.edgemac")]
        };
        NSData *bytes = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        if (!bytes) return 1;
        [[NSFileHandle fileHandleWithStandardOutput] writeData:bytes];
        puts("");
    }
    return 0;
}
