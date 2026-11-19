import Foundation
import CryptoKit

func sha(_ data:Data)->String {
    SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()
}

// A UI projection omits whitespace and transport delimiters. Its digest is not the HAR entity digest.
// Accept complete individual JSON records only, unique keys, bounded token shapes and the original service id.
func panelProjection(_ s:String,_ fileDigest:String)->[String:Any] {
    let lines=s.split(whereSeparator:\.isNewline)
    guard (2...3).contains(lines.count),s.utf8.count<=16384 else{return [:]}
    var kinds=[String](),progress=[Double]()
    for part in lines {
        var text=String(part).trimmingCharacters(in:.whitespaces)
        if text.hasPrefix("data:"){text=String(text.dropFirst(5)).trimmingCharacters(in:.whitespaces)}
        let raw=Data(text.utf8)
        guard text.hasPrefix("{"),text.hasSuffix("}"),!text.contains("\\"),let decoded=try? JSONSerialization.jsonObject(with:raw),let record=decoded as? [String:Any],
              let id=record["file_id"] as? String,sha(Data(id.utf8))==fileDigest,
              let kind=record["event"] as? String, let num=record["progress"] as? NSNumber,
              CFGetTypeID(num) != CFBooleanGetTypeID(),num.doubleValue.isFinite,(0...100).contains(num.doubleValue) else{return [:]}
        // Reject repeated identity/state fields at any nesting depth. Competing states stay ambiguous.
        for key in ["file_id","event","progress"] {
            let pattern="\u{22}"+key+"\u{22}\\s*:"
            guard let regex=try? NSRegularExpression(pattern:pattern),regex.numberOfMatches(in:text,range:NSRange(location:0,length:(text as NSString).length))==1 else{return [:]}
        }
        kinds.append(kind);progress.append(num.doubleValue)
    }
    let started="file.processing.started",ready="file.processing.file_ready",done="file.processing.completed",failed="file.processing.failed"
    var status="UNKNOWN"
    if kinds==[started,ready,done] && progress==progress.sorted() && progress.last==100 {status="FILE_PROCESSING_COMPLETED"}
    if kinds==[started,failed] || kinds==[started,ready,failed] {status="FILE_PROCESSING_FAILED"}
    return ["terminal":status,"frames":kinds.count,"sha":sha(Data(s.utf8))]
}
