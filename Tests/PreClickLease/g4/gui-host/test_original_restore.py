#!/usr/bin/env python3
"""Run the checked-in Swift restore branch with scripted original-window reads and no UI/AE calls.

Usage: python3 test_original_restore.py [PresentOriginal.swift]
The generated harness uses Foundation and Core Graphics value types. Exclusive JSON files in a private
temporary directory exercise one-shot and recovery behavior across repeated invocations.
"""

from pathlib import Path
import subprocess
import sys
import tempfile

PREFIX = r"""
import Foundation
import CoreGraphics

typealias Row = [String:Any]
typealias CGWindowID = UInt32
typealias Descriptor = NSAppleEventDescriptor
enum Identity { struct Refusal: Error { let reason: String; init(_ s:String){reason=s} } }
func require(_ v:Bool,_ reason:String) throws { if !v {throw Identity.Refusal(reason)} }
func read(_ state:URL,_ name:String) throws -> Row {
    guard let obj=try JSONSerialization.jsonObject(with:Data(contentsOf:state.appendingPathComponent(name))) as? Row else {throw Identity.Refusal("BAD_JSON")}
    return obj
}
final class Fake {
    var isMin=false, selectedOK=true, identityOK=true
    var owner="original";var reads:[Bool]=[]
    var surfaces:[(CGRect,CGWindowID)]=[]
    var failOffscreenAt:Int?;var offscreenCount=0;var actions:[String]=[];var refused:String?
    var stopAfterProof=false, loseUndoReply=false
    init(){resetFrames()}
    func resetFrames(){let t=(CGRect(x:10,y:10,width:1000,height:700),UInt32(74));surfaces=[t,t,t,t];offscreenCount=0;failOffscreenAt=nil}
}
func execute(_ state:URL,_ f:Fake) throws {
    var result:Row=[:]
    let family="edge",birth=f.owner,wid="expected-window",tid="expected-tab",marker="expected-document"
    let entry:Row?=["entryID":"expected-entry","timeOrigin":200000.0]
    func original() throws {
        try require(f.identityOK,"ORIGINAL_DOCUMENT_CHANGED")
        if f.stopAfterProof && FileManager.default.fileExists(atPath:state.appendingPathComponent("original-window-minimized-readback.json").path){
            f.stopAfterProof=false;throw Identity.Refusal("INTERRUPTION_AFTER_MINIMIZED_PROOF")
        }
    }
    func check() throws {try original()}
    func selected() throws -> Bool {try original();return f.selectedOK}
    func minimized() throws -> Bool {try original();if !f.reads.isEmpty{return f.reads.removeFirst()};return f.isMin}
    let win=wid
    func bounds(_ w:String) throws -> CGRect {try require(w==wid,"WRONG_WINDOW");return .zero}
    func coords(_ r:CGRect)->[CGFloat] {[r.minX,r.minY,r.width,r.height]}
    func foreground()->Bool {true}
    func settle() {}
    func offscreenOriginal() throws -> (CGRect,CGWindowID) {
        try original(); f.offscreenCount += 1
        try require(f.offscreenCount != f.failOffscreenAt && !f.surfaces.isEmpty,"SURFACE_REFUSED")
        return f.surfaces.removeFirst()
    }
    func setWindow(_ key:String,_ value:Descriptor,record flag:String) throws {
        try check()
        if key=="pidx"{f.actions.append("index");return}
        try require(key=="pmnd","UNKNOWN_MUTATION")
        if value.booleanValue { f.actions.append("min");f.isMin=true }
        else { f.actions.append("unmin"); f.isMin=false; if f.loseUndoReply {f.loseUndoReply=false;throw Identity.Refusal("UNDO_REPLY_LOST")} }
    }
"""
SUFFIX = r"""
}
@main enum Controls {
    static func main() throws {
        let base=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let fm=FileManager.default
        var cases=0,failures=0
        func run(_ title:String,_ body:(URL,Fake)throws ->Bool)throws {
            cases += 1
            let s=base.appendingPathComponent("t"+String(cases));try fm.createDirectory(at:s,withIntermediateDirectories:false)
            let f=Fake()
            let ok=try body(s,f)
            if !ok {failures += 1}
            print((ok ? "PASS " : "FAIL ")+title+" "+f.actions.joined(separator:","))
        }
        func invoke(_ s:URL,_ f:Fake)->Bool {
            do{try execute(s,f);f.refused=nil;return true}
            catch{f.refused=(error as? Identity.Refusal)?.reason ?? "IO_FAILURE";return false}
        }
        // Successful initial restore and later manual minimization: the saved terminal is read-only.
        try run("single-same-original-cycle-and-completed-reentry"){s,f in
            guard invoke(s,f), f.actions.filter({$0=="min"}).count==1,
                  f.actions.filter({$0=="unmin"}).count==1,!f.isMin else{return false}
            let n=f.actions;f.isMin=true
            return invoke(s,f) && f.actions==n && f.isMin
        }
        // The host may die after selecting the original but before the second complete proof.
        try run("second-sample-failure-does-not-repeat-index-or-start-minimize"){s,f in
            f.failOffscreenAt=2
            guard !invoke(s,f), !f.actions.contains("min") else{return false}
            let n=f.actions; f.resetFrames()
            _=invoke(s,f)
            return f.actions==n
        }
        try run("changed-cg-id-or-geometry-never-minimizes"){s,f in
            f.surfaces[1].1=999
            guard !invoke(s,f),!f.actions.contains("min") else{return false}
            let other=s.appendingPathComponent("geometry");try fm.createDirectory(at:other,withIntermediateDirectories:false)
            f.resetFrames(); f.surfaces[1].0=f.surfaces[1].0.offsetBy(dx:1,dy:0)
            return !invoke(other,f) && !f.actions.contains("min")
        }
        // Stop after the original minimize readback is durable but before issuing the undo.
        func interrupted(_ s:URL,_ f:Fake)->Bool {
            f.stopAfterProof=true;let ok=invoke(s,f)
            return !ok && f.isMin && f.actions.filter({$0=="min"}).count==1
        }
        try run("interrupted-and-confirmed-current-owner-may-only-undo"){s,f in
            guard interrupted(s,f) else{return false}
            let n=f.actions.count
            return invoke(s,f) && Array(f.actions.dropFirst(n))==["unmin"] && !f.isMin
        }
        try run("foreign-owner-cannot-clean-up"){s,f in
            guard interrupted(s,f) else{return false}
            f.owner="another-born-process";let n=f.actions
            return !invoke(s,f) && f.actions==n
        }
        try run("expired-or-future-readback-no-mutation"){s,f in
            guard interrupted(s,f) else{return false}
            let url=s.appendingPathComponent("original-window-minimized-readback.json")
            var obj=try read(s,url.lastPathComponent); let n=f.actions
            for d in [-16.0,1.0] {
                obj["atUptime"]=ProcessInfo.processInfo.systemUptime+d
                try JSONSerialization.data(withJSONObject:obj).write(to:url)
                if invoke(s,f) || f.actions != n {return false}
            }
            return true
        }
        try run("unknown-undo-ownership-and-interleaved-manual-minimize"){s,f in
            guard interrupted(s,f) else{return false}
            try fm.removeItem(at:s.appendingPathComponent("original-window-minimized-readback.json"))
            let n=f.actions; f.reads=[false,true,true,true]
            _=invoke(s,f)
            guard f.actions==n else {return false}
            // An undo reached the native window, but the response never arrived. Another actor
            // minimizes the same window again before the old 15-second proof ages out.
            let other=s.appendingPathComponent("lost-undo");try fm.createDirectory(at:other,withIntermediateDirectories:false)
            let g=Fake();g.loseUndoReply=true
            guard !invoke(other,g),!g.isMin,g.actions.filter({$0=="unmin"}).count==1 else{return false}
            g.isMin=true;let before=g.actions
            _=invoke(other,g)
            if !g.isMin || g.actions != before {print("  lost undo reply and subsequent manually minimized original: "+g.actions.joined(separator:","))}
            return g.isMin && g.actions==before
        }
        try run("changed-original-document-no-new-action"){s,f in
            f.identityOK=false
            let ok=invoke(s,f)
            return !ok && f.actions.isEmpty
        }
        print("controls=\(cases) failures=\(failures)")
        if failures>0 {exit(1)}
    }
}
"""
def branch(source):
    start=source.index('if mode == "restore" {')+len('if mode == "restore" {')
    return source[start:source.index('} else if try minimized()',start)]

def main():
    src=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).with_name('PresentOriginal.swift')
    with tempfile.TemporaryDirectory(prefix='riftlet-restore-controls-') as folder:
        root=Path(folder);code=root/'main.swift';exe=root/'controls'
        code.write_text(PREFIX+branch(src.read_text())+SUFFIX)
        subprocess.run(['xcrun','swiftc','-parse-as-library',code,'-o',exe],check=True)
        raise SystemExit(subprocess.run([exe,root]).returncode)
if __name__=='__main__': main()
