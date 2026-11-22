#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>
#import <libproc.h>
#import <poll.h>

static NSString *const draft = @"Riftlet QA: preserve this original draft while attaching images.";
static NSString *const phrase = @"preserve this original draft";
static NSString *const website = @"https://chatgpt.com/?temporary-chat=true";
static void require(BOOL ok, const char *reason) {
    if (!ok) { fprintf(stderr, "%s\n", reason); exit(2); }
}
static id attr(id element, NSString *key) {
    CFTypeRef result = NULL;
    if (!element || AXUIElementCopyAttributeValue((__bridge AXUIElementRef)element, (__bridge CFStringRef)key, &result) != kAXErrorSuccess) return nil;
    return CFBridgingRelease(result);
}
static BOOL settable(id e, NSString *key) {
    Boolean ok = false;
    return AXUIElementIsAttributeSettable((__bridge AXUIElementRef)e, (__bridge CFStringRef)key, &ok) == kAXErrorSuccess && ok;
}
static CFRange rangeOf(id e) {
    id value = attr(e, @"AXSelectedTextRange"); CFRange r = {-1,-1};
    require(value && CFGetTypeID((__bridge CFTypeRef)value)==AXValueGetTypeID() &&
            AXValueGetValue((__bridge AXValueRef)value,kAXValueCFRangeType,&r),"RANGE_UNAVAILABLE");
    return r;
}
static NSDictionary *reply(const char *prompt, NSString *token) {
    puts(prompt); fflush(stdout);
    struct pollfd f={STDIN_FILENO,POLLIN,0}; char buf[4096]={0};
    require(poll(&f,1,45000)==1 && fgets(buf,sizeof(buf),stdin), "ORIGINAL_SCOPE_CONFIRMATION_MISSING");
    NSData *d = [NSData dataWithBytes:buf length:strlen(buf)];
    NSDictionary *v = [NSJSONSerialization JSONObjectWithData:d options:0 error:NULL];
    require([v isKindOfClass:NSDictionary.class] && [v[@"token"] isEqual:token] && [v[@"geometry"] isKindOfClass:NSDictionary.class],"BAD_ROUTE_RESPONSE");
    return v[@"geometry"];
}
static CGRect rectOf(id e) {
    id pos=attr(e,@"AXPosition"),size=attr(e,@"AXSize");CGPoint xy={0};CGSize wh={0};
    require(pos && size && CFGetTypeID((__bridge CFTypeRef)pos)==AXValueGetTypeID() && CFGetTypeID((__bridge CFTypeRef)size)==AXValueGetTypeID() &&
      AXValueGetValue((__bridge AXValueRef)pos,kAXValueCGPointType,&xy) && AXValueGetValue((__bridge AXValueRef)size,kAXValueCGSizeType,&wh) && wh.width>0 && wh.height>0,"AX_FRAME_UNAVAILABLE");
    return (CGRect){xy,wh};
}
static id ancestor(id e,NSString *role) {
    for(int i=0;i<64 && e;i++,e=attr(e,@"AXParent")) if([attr(e,@"AXRole") isEqual:role])return e;
    return nil;
}
static id exactWebArea(id w) {
    NSMutableArray *queue=[NSMutableArray arrayWithObject:w]; id found=nil;
    for(NSUInteger i=0;i<queue.count;i++) {
      require(queue.count<=2048,"AX_SUBTREE_BOUND_EXCEEDED");id e=queue[i];
      if ([attr(e,@"AXRole") isEqual:@"AXWebArea"]) {
        id u=attr(e,@"AXURL"); NSString *url=[u isKindOfClass:NSURL.class]?[u absoluteString]:u;
        if([url isEqual:website]) {require(!found,"MULTIPLE_QA_WEB_AREAS");found=e;}
        continue;
      }
      NSArray *children=attr(e,@"AXChildren"); if([children isKindOfClass:NSArray.class]) [queue addObjectsFromArray:children];
    }
    require(found!=nil,"ORIGINAL_AX_WEB_AREA_UNAVAILABLE");return found;
}
static double measured(NSDictionary *g,NSString *key) {
    id n=g[key];require([n isKindOfClass:NSNumber.class] && isfinite([n doubleValue]),"INVALID_DOM_GEOMETRY");return [n doubleValue];
}
static BOOL near(double a,double b,double tolerance) {return fabs(a-b)<=tolerance;}
static id mappedField(id app,id win,id web,NSDictionary *g) {
    CGRect v=rectOf(web),w=rectOf(win);
    double vw=measured(g,@"vw"),vh=measured(g,@"vh");require(vw>0 && vh>0,"BAD_VIEWPORT");
    double scale=v.size.width/vw,sy=v.size.height/vh;
    require(scale>=0.25 && scale<=5 && near(scale,sy,0.025*scale),"AX_AND_DOM_VIEWPORT_SCALES_DIFFER");
    // A web area including a scrolled document or another native window fails here.
    require(near(w.origin.x,measured(g,@"screenLeft"),4) && near(w.origin.y,measured(g,@"screenTop"),4) &&
        near(w.size.width,measured(g,@"outerWidth"),5) && near(w.size.height,measured(g,@"outerHeight"),5),"AX_AND_DOM_WINDOW_FRAMES_DIFFER");
    CGRect rr=CGRectMake(v.origin.x+measured(g,@"x")*scale,v.origin.y+measured(g,@"y")*sy,
                         measured(g,@"width")*scale,measured(g,@"height")*sy);
    require(rr.size.width>4 && rr.size.height>3 && CGRectContainsRect(CGRectInset(v,-1,-1),rr) && CGRectContainsRect(CGRectInset(w,-1,-1),rr),"EDITOR_OUTSIDE_ORIGINAL_VIEWPORT");
    id resolved=nil;
    for(NSNumber *ratio in @[@0.32,@0.68]) {
      CGPoint point=CGPointMake(rr.origin.x+rr.size.width*ratio.doubleValue,CGRectGetMidY(rr));
      AXUIElementRef hit=NULL;
      require(AXUIElementCopyElementAtPosition((__bridge AXUIElementRef)app,point.x,point.y,&hit)==kAXErrorSuccess && hit,"AX_HIT_UNAVAILABLE");
      id node=CFBridgingRelease(hit);id field=ancestor(node,@"AXTextArea");
      require(field && [ancestor(field,@"AXWebArea") isEqual:web] && [attr(field,@"AXWindow") isEqual:win] && [attr(field,@"AXEnabled") boolValue],"HIT_NOT_ORIGINAL_EDITABLE");
      CGRect sr=rectOf(field);
      require(near(sr.origin.x,rr.origin.x,3) && near(sr.origin.y,rr.origin.y,3) && near(sr.size.width,rr.size.width,4) &&
         near(sr.size.height,rr.size.height,4),"AX_AND_DOM_EDITOR_FRAMES_DIFFER");
      require(!resolved || [resolved isEqual:field],"MULTIPLE_EDITOR_HITS");resolved=field;
    }
    return resolved;
}
int main(int argc,const char **argv) {
  @autoreleasepool {
    require(argc==5,"USAGE: ax_prepare chrome|edge PID KERNEL_SESSION GEOMETRY_JSON");
    NSString *family=@(argv[1]), *bundle=nil,*exe=nil;
    if([family isEqual:@"chrome"]) {bundle=@"com.google.Chrome";exe=@"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";}
    if([family isEqual:@"edge"]) {bundle=@"com.microsoft.edgemac";exe=@"/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge";}
    require(bundle!=nil,"BROWSER_FAMILY_REFUSED");
    pid_t pid=(pid_t)[@(argv[2]) intValue]; NSString *session=@(argv[3]);
    require(pid>1 && AXIsProcessTrusted(),"ACCESSIBILITY_UNAVAILABLE");
    id app=CFBridgingRelease(AXUIElementCreateApplication(pid));
    __block id field=nil,window=nil,web=nil;
    __block NSDictionary *geometry=[NSJSONSerialization JSONObjectWithData:[@(argv[4]) dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    require([geometry isKindOfClass:NSDictionary.class],"INVALID_INITIAL_GEOMETRY");
    void (^guardRoute)(BOOL)=^(BOOL requireFocus){
      struct proc_bsdinfo info;char path[PROC_PIDPATHINFO_MAXSIZE]={0};
      require(proc_pidinfo(pid,PROC_PIDTBSDINFO,0,&info,sizeof(info))==sizeof(info) &&
          [[NSString stringWithFormat:@"%@-kernel-v1:%d:%llu:%llu",family,pid,info.pbi_start_tvsec,info.pbi_start_tvusec] isEqual:session] &&
          proc_pidpath(pid,path,sizeof(path))>0 && [@(path) isEqual:exe],"PROCESS_BIRTH_OR_EXECUTABLE_CHANGED");
      NSRunningApplication *front=NSWorkspace.sharedWorkspace.frontmostApplication;
      require(front.processIdentifier==pid && [front.bundleIdentifier isEqual:bundle],"NOT_FOREGROUND_ORIGINAL_APP");
      id w=attr(app,@"AXFocusedWindow");require(w,"ORIGINAL_WINDOW_MISSING");
      if(!window){window=w;web=exactWebArea(w);}
      require([w isEqual:window],"ORIGINAL_AX_WINDOW_CHANGED");
      id e=mappedField(app,window,web,geometry);
      if(!field)field=e;
      require([e isEqual:field],"ORIGINAL_AX_ELEMENT_CHANGED");
      if(requireFocus)require([attr(app,@"AXFocusedUIElement") isEqual:field] && [attr(field,@"AXFocused") boolValue],"ORIGINAL_AX_EDITOR_NOT_FOCUSED");
    };
    guardRoute(NO);
    NSString *writeAttribute = settable(field,@"AXSelectedText") ? @"AXSelectedText" : @"AXValue";
    require(settable(field,writeAttribute) && settable(field,@"AXSelectedTextRange"),"ORIGINAL_EDITOR_AX_ATTRIBUTES_READ_ONLY");
    BOOL already=[attr(app,@"AXFocusedUIElement") isEqual:field] && [attr(field,@"AXFocused") boolValue];
    if(!already) {
      require(settable(field,@"AXFocused") && [attr(field,@"AXValue") isEqual:@""],"MAPPED_EMPTY_EDITOR_CANNOT_FOCUS");
      geometry=reply("CAN_FOCUS_ORIGINAL",@"FOCUS_ONCE");guardRoute(NO);
      require([attr(field,@"AXValue") isEqual:@""] && AXUIElementSetAttributeValue((__bridge AXUIElementRef)field,CFSTR("AXFocused"),kCFBooleanTrue)==kAXErrorSuccess,"MAPPED_FOCUS_UNCONFIRMED");
    }
    guardRoute(YES);CFRange r=rangeOf(field);
    require([attr(field,@"AXValue") isEqual:@""] && r.location==0 && r.length==0,"NOT_EMPTY_ORIGINAL_DRAFT");
    geometry=reply("READY_EMPTY",@"INSERT_ONCE");guardRoute(YES);
    r=rangeOf(field);
    require([attr(field,@"AXValue") isEqual:@""] && r.location==0 && r.length==0,"DRAFT_CHANGED_BEFORE_INSERT");
    require(AXUIElementSetAttributeValue((__bridge AXUIElementRef)field,(__bridge CFStringRef)writeAttribute,(__bridge CFStringRef)draft)==kAXErrorSuccess,"INSERT_UNCERTAIN_DO_NOT_REISSUE");
    require([attr(app,@"AXFocusedUIElement") isEqual:field] && [attr(field,@"AXValue") isEqual:draft],"INSERT_UNCONFIRMED_DO_NOT_REISSUE");
    geometry=reply("TEXT_PRESENT",@"SELECT_ONCE");guardRoute(YES);
    require([attr(field,@"AXValue") isEqual:draft],"DRAFT_CHANGED_BEFORE_SELECTION");
    NSRange expected=[draft rangeOfString:phrase];CFRange selected=CFRangeMake(expected.location,expected.length);
    AXValueRef value = AXValueCreate(kAXValueCFRangeType,&selected);
    require(value!=NULL,"RANGE_CONSTRUCTION_FAILED");
    AXError err=AXUIElementSetAttributeValue((__bridge AXUIElementRef)field,CFSTR("AXSelectedTextRange"),value);
    CFRelease(value);require(err==kAXErrorSuccess,"SELECTION_UNCERTAIN_DO_NOT_REISSUE");
    guardRoute(YES);r=rangeOf(field);
    require([attr(field,@"AXValue") isEqual:draft] && [attr(field,@"AXSelectedText") isEqual:phrase] &&
        r.location==selected.location && r.length==selected.length,"FINAL_RANGE_UNCONFIRMED");
    puts("SELECTION_PRESENT");return 0;
  }
}
