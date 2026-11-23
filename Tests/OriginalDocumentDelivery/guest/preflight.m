#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <Carbon/Carbon.h>
static NSNumber *authorized(NSString *bundleID) {
    AEDesc target;
    NSData *name=[bundleID dataUsingEncoding:NSUTF8StringEncoding];
    OSStatus status=AECreateDesc(typeApplicationBundleID,name.bytes,(Size)name.length,&target);
    if(status==noErr) {
        status=AEDeterminePermissionToAutomateTarget(&target,kAECoreSuite,kAEGetData,false);
        AEDisposeDesc(&target);
    }
    return @(status);
}
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSDictionary *session=CFBridgingRelease(CGSessionCopyCurrentDictionary());
        NSArray *windows=CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly|kCGWindowListExcludeDesktopElements,kCGNullWindowID));
        NSMutableDictionary *counts=[NSMutableDictionary dictionary];
        NSMutableArray *panels=[NSMutableArray array];
        for(NSDictionary *win in windows) {
            NSString *name=win[(id)kCGWindowOwnerName];
            if(![@[@"loginwindow",@"SecurityAgent",@"UserNotificationCenter",@"System Settings",@"CoreServicesUIAgent",@"Google Chrome",@"Microsoft Edge"] containsObject:name]) continue;
            counts[name]=@([counts[name] intValue]+1);
            if([name isEqualToString:@"UserNotificationCenter"]) [panels addObject:win[(id)kCGWindowNumber]];
        }
        NSDictionary *result=@{@"sessionPresent":@(session!=nil),@"sessionLocked":session[@"CGSSessionScreenIsLocked"] ?: [NSNull null],
            @"loginDone":session[@"kCGSessionLoginDoneKey"] ?: [NSNull null],
            @"cropAllowed":@(CGPreflightScreenCaptureAccess()),@"systemDialogIDs":panels,@"systemWindows":counts,@"front":NSWorkspace.sharedWorkspace.frontmostApplication.bundleIdentifier ?: @"",
            @"AXTrusted":@(AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(__bridge id)kAXTrustedCheckOptionPrompt:@NO})),
            @"AEChrome":argc>1?authorized(@"com.google.Chrome"):[NSNull null],@"AEEdge":argc>1?authorized(@"com.microsoft.edgemac"):[NSNull null]};
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
        fwrite(data.bytes,1,data.length,stdout);fputc('\n',stdout);
    }
}
