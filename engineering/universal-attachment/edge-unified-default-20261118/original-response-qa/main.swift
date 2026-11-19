import Foundation

func emit(_ value:[String:Any]) {
    FileHandle.standardOutput.write((try! JSONSerialization.data(withJSONObject:value,options:.sortedKeys))+Data([10]))
}
emit(policySelftest())
 let id="file-ExampleNeutral",hash=sha(Data(id.utf8)),prefix="file.processing."
 func frame(_ key:String,_ val:String,_ file:String)->String {"{\"event\":\""+prefix+key+"\",\"progress\":"+val+",\"file_id\":\""+file+"\"}"}
 let a=frame("started","0",id),b=frame("file_ready","45",id),c=frame("completed","100",id),f=frame("failed","50",id)
 let good="FILE_PROCESSING_COMPLETED",bad="FILE_PROCESSING_FAILED",unknown="UNKNOWN"
 let tests:[([String],String)]=[([a,b,c],good),([a,f],bad),([a,b,f],bad),([a,b,c,f],unknown),([a,c],unknown),([a,frame("file_ready","70","file-Other"),c],unknown),([c],unknown),([a,b,frame("completed","99",id)],unknown),([a,b,c,c],unknown),([a,b,c.replacingOccurrences(of:"100",with:"100,\"progress\":100")],unknown),([a,b,c.replacingOccurrences(of:"100",with:"true")],unknown),([a,b,frame("completed","NaN",id)],unknown),([a,b,frame("completed","120",id)],unknown),(["data: "+a,"data: "+b,"data: "+c],good)]
 let ok=tests.allSatisfy{(lines,want) in (panelProjection(lines.joined(separator:"\n"),hash)["terminal"] as? String ?? unknown)==want}
 emit(["offlineSyntheticPanelCases":tests.count,"success":ok,"newCommercialRequests":0]);precondition(ok)
