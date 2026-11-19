import Foundation

/// A per-click execution capability check. Edge's dictionary does not specify
/// worlds: the execute realm must retain an original-document private closure,
/// while a javascript: bootstrap must NOT see that realm's own global property.
/// This checks actual runtime behavior, not a browser-family assumption. It is
/// not an authenticated service receipt; native identity, editor witness and
/// the shared attachment observer remain independently mandatory.
struct EdgeExecutionWorldWitness: Sendable {
    private let id = UUID().uuidString.lowercased()
    private let secret = UUID().uuidString.lowercased()
    private var key: String { "__riftletEdgeExecution_" + id }
    private var attribute: String { "data-riftlet-edge-execution-" + id }

    /// Both original-document capabilities are created in one execute event on
    /// the frozen tab. This saves a native round trip inside the unchanged
    /// 150 ms click budget. A page that became background during the original
    /// ID/address read must refuse before installing a witness: a past blur
    /// cannot be recovered by listeners installed later. Editor focus is not
    /// required. The final native selection and all later full checks remain.
    func prepareAndBind(_ witness: ChromeClickDocumentWitness, address: String,
                        program: WebPageProgram) throws -> String {
        let binding = try witness.bindScript(address: address, program: program)
        return """
        /* edge-click-prepare-and-pin */
        (()=>{if(document.visibilityState!=='visible'||typeof document.hasFocus!=='function'
          ||document.hasFocus()!==true)return 'refused';
        if((\(prepare))!=='prepared')return 'refused';return (\(binding));})()
        """
    }

    var prepare: String {
        """
        /* edge-world-prepare */
        (()=>{const key='\(key)',secret='\(secret)',root=document.documentElement,
          entry=globalThis.navigation?.currentEntry,address=location.href;
        if(top!==self||!root||!entry||Object.prototype.hasOwnProperty.call(globalThis,key))return 'refused';
        const current=()=>document.documentElement===root&&location.href===address&&navigation.currentEntry?.id===entry.id;
        let verified=false;
        const capability=Object.freeze({confirm:()=>{if(current()&&root.getAttribute('\(attribute)')===secret){
          root.removeAttribute('\(attribute)');verified=true;}return verified&&current();},current:()=>verified&&current()});
        Object.defineProperty(globalThis,key,{value:capability,configurable:true});
        setTimeout(()=>{delete globalThis[key];root.removeAttribute('\(attribute)');},60000);
        return 'prepared';})()
        """
    }
    var bootstrap: String {
        """
        /* edge-world-bootstrap */
        (()=>{if(!Object.prototype.hasOwnProperty.call(globalThis,'\(key)'))
          document.documentElement.setAttribute('\(attribute)','\(secret)');})()
        """
    }
    var confirm: String {
        "/* edge-world-confirm */ (()=>globalThis['\(key)']?.confirm()===true?'verified':'refused')()"
    }
    var validate: String {
        "/* edge-world-validate */ (()=>globalThis['\(key)']?.current()===true?'verified':'refused')()"
    }
}
