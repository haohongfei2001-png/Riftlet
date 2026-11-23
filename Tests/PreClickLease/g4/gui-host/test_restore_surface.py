#!/usr/bin/env python3
"""Compile the original AX and CG admission functions using deterministic, local-only samples."""
from pathlib import Path
import sys, tempfile, subprocess

PROLOGUE=r'''
import Foundation
import CoreGraphics
struct W {var role:String?="AXWindow";var subrole:String?="AXStandardWindow"; var frame:CGRect?}
struct T {var window:String;var tab:String}
typealias AXUIElement=W
let kAXRoleAttribute="role",kAXSubroleAttribute="subrole"
enum Identity {struct Refusal:Error {let reason:String;init(_ s:String){reason=s}}}
func require(_ ok:Bool,_ reason:String)throws{if !ok{throw Identity.Refusal(reason)}}
func ax(_ item:W,_ key:String)->Any? { key=="role" ? item.role : item.subrole }
func axFrame(_ item:W)->CGRect? {item.frame}
let target=CGRect(x:0,y:0,width:400,height:300), other=CGRect(x:20,y:20,width:400,height:300)
final class F {
    var regular:[W]?=[W(frame:other)]; var active:T?=T(window:"88",tab:"21")
    var isHidden=false, mini=false, insideDisplay=true, current=true;var peers:[CGRect]=[other]
    var all:[[String:Any]]?=[], on:[[String:Any]]?=[]
}
func surface(_ id:UInt32,_ frame:CGRect)->[String:Any] {
    [kCGWindowOwnerPID as String:Int32(431),kCGWindowLayer as String:0,kCGWindowNumber as String:id,
     kCGWindowBounds as String:frame.dictionaryRepresentation as NSDictionary]
}
func perform(_ f:F)throws->(CGRect,CGWindowID){
    typealias Row=[String:Any]
    let pid:Int32=431,wid="88",tid="21",win="88";let app=f
    func check()throws{try require(f.current,"IDENTITY_CHANGED")}
    func bounds(_ arg:String)throws->CGRect{try require(arg==wid,"WRONG_WINDOW");return target}
    func minimized()throws->Bool{f.mini}
    func peerBounds()throws->[CGRect]{f.peers}
    func same(_ a:CGRect,_ b:CGRect)->Bool {zip([a.minX,a.minY,a.width,a.height],[b.minX,b.minY,b.width,b.height]).allSatisfy{abs($0-$1)<=1}}
'''
EPILOGUE=r'''
    return try offscreenOriginal()
}
@main enum Controls {
    static func main(){
        let cases:[(String,(F)->Void,String?)]=[
          ("one-complete-offscreen-source", {_ in},nil),
          ("wrong-native-active-tab",{$0.active?.tab="22"},"ORIGINAL_WINDOW_ACTIVE_TAB_CHANGED"),
          ("another-native-window-same-rect",{$0.peers=[target]},"NATIVE_FRAME_AMBIGUOUS"),
          ("unknown-AX-role-subrole-or-frame",{$0.regular=[W(role:nil,subrole:"AXStandardWindow",frame:other)]},"AX_WINDOW_ROLE_UNAVAILABLE"),
          ("missing-AX-subrole",{$0.regular=[W(role:"AXWindow",subrole:nil,frame:target)]},"AX_WINDOW_SUBROLE_UNAVAILABLE"),
          ("unreadable-standard-window-frame",{$0.regular=[W(frame:nil)]},"AX_WINDOW_BOUNDS_UNAVAILABLE"),
          ("existing-original-AX-window",{$0.regular=[W(frame:target)]},"AX_ORIGINAL_ALREADY_AVAILABLE"),
          ("two-CG-owners-for-frame",{$0.all=[surface(91,target),surface(92,target)]},"NO_UNIQUE_OFFSCREEN_ORIGINAL_CG_WINDOW"),
          ("same-CG-number-onscreen-after-move",{$0.on=[surface(91,other)]},"NO_UNIQUE_OFFSCREEN_ORIGINAL_CG_WINDOW"),
          ("onscreen-at-enrolled-frame-with-other-number",{$0.on=[surface(92,target)]},"NO_UNIQUE_OFFSCREEN_ORIGINAL_CG_WINDOW"),
          ("unreadable-browser-CG-row",{$0.on=[[kCGWindowOwnerPID as String:Int32(431),kCGWindowLayer as String:0]]},"CG_WINDOW_UNREADABLE"),
          ("missing-CG-inventory",{$0.all=nil},"WINDOWSERVER_UNAVAILABLE")
        ]
        var failed=0
        for (name,configure,expected) in cases {
            let f=F();f.all=[surface(91,target)];configure(f);var outcome:String?
            do{let (r,id)=try perform(f);if r != target || id != 91 {outcome="WRONG_SURFACE"}}
            catch {outcome=(error as? Identity.Refusal)?.reason ?? "OTHER"}
            print((outcome==expected ? "PASS " : "FAIL ")+name)
            if outcome != expected{failed += 1}
        }
        print("controls=\(cases.count) failures=\(failed)");if failed>0{exit(1)}
    }
}
'''
def once(s,a,b):
    if s.count(a)!=1:raise AssertionError('Host API seam changed: '+a)
    return s.replace(a,b,1)
def isolated(src):
    left=src.index('func matchingAX('); right=src.index('func minimized()',left)
    ax=src[left:right]
    ax=once(ax,'ax(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]','f.regular')
    left=src.index('func offscreenOriginal()'); right=src.index('func raiseOriginal(',left)
    gate=src[left:right]
    gate=once(gate,'try ChromeActiveTabDescriptor.identity(in: Identity.get(proc, Identity.property("acTa", win)))','f.active')
    start=gate.index('guard let primary = NSScreen.')
    end=gate.index('try require(inVisibleFrame,',start)
    gate=gate[:start]+'let inVisibleFrame = f.insideDisplay\n'+gate[end:]
    gate=once(gate,'CGWindowListCopyWindowInfo([options, .excludeDesktopElements], kCGNullWindowID) as? [Row]','(options == .optionAll ? f.all : f.on)')
    return ax+gate
def main():
    src=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).with_name('PresentOriginal.swift')
    with tempfile.TemporaryDirectory(prefix='riftlet-offscreen-controls-') as name:
        root=Path(name); swift=root/'Controls.swift';exe=root/'Controls'
        swift.write_text(PROLOGUE+isolated(src.read_text())+EPILOGUE)
        subprocess.run(['xcrun','swiftc','-parse-as-library',swift,'-o',exe],check=True)
        raise SystemExit(subprocess.run([exe]).returncode)
if __name__=='__main__':main()
