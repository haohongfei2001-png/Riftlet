import Foundation

struct NetworkCountFacts {
    var networkTabSelected:Bool = true
    var originalDockCount:Int = 1
    var recordingControlCount:Int = 1
    var sanitizedExportControlCount:Int = 1
    var filterValuesReadable:Bool = true
    var filterNonempty:Bool = false
    var headerTableCount:Int = 0
    var visibleRequestRows:Int = 0
    var rowCountAttribute:Int? = nil
    var totalRequestCounters:[Int] = []
    var treeReadSucceeded:Bool = true
}
// Exact closed labels only. A filtered count uses the denominator; "0 / 7" is never empty.
func explicitRequestTotal(_ text:String)->Int? {
    let s=text.trimmingCharacters(in:.whitespacesAndNewlines)
    let patterns=[#"^([0-9]{1,6})(?:\s*/\s*([0-9]{1,6}))? requests?$"#,
                  #"^([0-9]{1,6})(?:\s*/\s*([0-9]{1,6}))?\s*个请求$"#,
                  #"^([0-9]{1,6})(?:\s*/\s*([0-9]{1,6}))?\s*項要求$"#,
                  #"^([0-9]{1,6})(?:\s*/\s*([0-9]{1,6}))?\s*个网络请求$"#]
    for pattern in patterns {
        let regex=try! NSRegularExpression(pattern:pattern)
        guard let match=regex.firstMatch(in:s,range:NSRange(location:0,length:(s as NSString).length)) else{continue}
        let range=match.range(at:match.range(at:2).location==NSNotFound ? 1:2)
        return Int((s as NSString).substring(with:range))
    }
    return nil
}
func networkBaselineProof(_ f:NetworkCountFacts)->String? {
    guard f.treeReadSucceeded,f.networkTabSelected,f.originalDockCount==1,f.recordingControlCount==1,
          f.sanitizedExportControlCount==1,f.filterValuesReadable,!f.filterNonempty,
          f.headerTableCount<=1,f.visibleRequestRows>=0,
          f.totalRequestCounters.allSatisfy({$0>=0}),Set(f.totalRequestCounters).count<=1 else{return nil}
    if f.visibleRequestRows==0 {
        let explicitFooter = !f.totalRequestCounters.isEmpty && f.totalRequestCounters.allSatisfy{$0==0}
        let explicitTable = f.headerTableCount==1 && f.rowCountAttribute==0
        guard explicitFooter || explicitTable,
              f.rowCountAttribute.map({$0==0}) ?? true,
              f.totalRequestCounters.allSatisfy({$0==0}) else{return nil}
        return explicitFooter ? "EXPLICIT_ZERO_REQUEST_COUNTER" : "NAMED_NETWORK_AX_ROWCOUNT_ZERO"
    }
    guard f.headerTableCount==1,
          f.rowCountAttribute.map({$0>=f.visibleRequestRows}) ?? true,
          f.totalRequestCounters.allSatisfy({$0>=f.visibleRequestRows}) else{return nil}
    return "NONEMPTY_NAMED_NETWORK_TABLE"
}
func originalPayloadPair(_ before:(String,String),_ after:(String,String),_ known:Set<String>,_ otherSelected:Int)->Bool {
    before==after && known.contains(before.0) && before.1.range(of:"^[a-f0-9]{64}$",options:.regularExpression) != nil && otherSelected==0
}
func policySelftest()->[String:Any] {
    var cases=0
    func yes(_ f:NetworkCountFacts,_ want:Bool){precondition((networkBaselineProof(f) != nil)==want);cases+=1}
    var f=NetworkCountFacts();yes(f,false) // A missing table is not zero.
    f.totalRequestCounters=[0];yes(f,true)
    f.totalRequestCounters=[0,0];yes(f,true)
    f.totalRequestCounters=[0,2];yes(f,false)
    f.totalRequestCounters=[2];yes(f,false)
    f.totalRequestCounters=[];f.headerTableCount=1;f.rowCountAttribute=0;yes(f,true)
    f.rowCountAttribute=nil;yes(f,false)
    f.rowCountAttribute=1;yes(f,false)
    f.rowCountAttribute=0;f.totalRequestCounters=[3];yes(f,false)
    f.totalRequestCounters=[0];f.treeReadSucceeded=false;yes(f,false)
    f.treeReadSucceeded=true;f.networkTabSelected=false;yes(f,false)
    f.networkTabSelected=true;f.originalDockCount=2;yes(f,false)
    f.originalDockCount=1;f.recordingControlCount=0;yes(f,false)
    f.recordingControlCount=1;f.sanitizedExportControlCount=0;yes(f,false)
    f.sanitizedExportControlCount=1;f.filterNonempty=true;yes(f,false)
    f.filterNonempty=false;f.filterValuesReadable=false;yes(f,false)
    f.filterValuesReadable=true;f.headerTableCount=2;yes(f,false)
    f.headerTableCount=1;f.visibleRequestRows=1;yes(f,false)
    f.rowCountAttribute=1;f.totalRequestCounters=[1];yes(f,true)
    f.totalRequestCounters=[];yes(f,true)
    f.headerTableCount=0;yes(f,false)
    for (s,want) in [("0 requests",0),("0 request",0),("0 / 0 requests",0),("0 / 9 requests",9),("12 requests",12),("0 个请求",0),("0 / 3 个请求",3),("0 B transferred",-1),("Currently recording network activity",-1),("No network activity recorded",-1),("error",-1),("0 requests extra",-1),("requests 0",-1)] {
        precondition((explicitRequestTotal(s) ?? -1)==want);cases+=1
    }
    let a=("a",String(repeating:"a",count:64)),b=("b",String(repeating:"b",count:64))
    precondition(originalPayloadPair(a,a,["a","b"],0));cases+=1
    precondition(!originalPayloadPair(a,b,["a","b"],0));cases+=1
    precondition(!originalPayloadPair(a,a,["b"],0));cases+=1
    precondition(!originalPayloadPair(a,a,["a"],1));cases+=1
    return ["PASS":true,"policyCases":cases,"GUIActions":0,"networkRequests":0]
}
