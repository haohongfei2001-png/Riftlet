import AppKit
import CryptoKit

/// Never searches for or starts a browser. Uses the existing hosted round's
/// child, birth, ephemeral URL and newly generated, public neutral test PNG.
@main
private enum EdgeNeutralPickerCLI {
    @MainActor static func main() {
        let args = CommandLine.arguments
        guard args.count == 5, let pid = pid_t(args[1]), pid > 1, let url = URL(string: args[3]),
              let fixture = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNI6ZgJAALZAYa2S+pDAAAAAElFTkSuQmCC")
        else { exit(64) }
        let file = URL(fileURLWithPath: args[4]).standardizedFileURL
        do {
            guard try Data(contentsOf: file) == fixture else { exit(64) }
            let sha256 = SHA256.hash(data: fixture).map { String(format: "%02x", $0) }.joined()
            let outcome = try EdgeConversationPicker.handOffNeutralEdge(pid: pid, birth: args[2], address: url,
                directory: file.deletingLastPathComponent(), file: file, bytes: Int64(fixture.count), sha256: sha256)
            switch outcome {
            case .refusedBeforeEntry: print("REFUSED_BEFORE_ENTRY")
            case .entryAttempted: print("ENTRY_ATTEMPTED_NO_FILE_CONFIRMATION")
            case .inputAttempted: print("EXACT_FILE_SUBMIT_ATTEMPTED")
            case .uncertain: print("ORIGINAL_ACTION_UNKNOWN")
            case .alreadyAttempted: print("ORIGINAL_INPUT_INTENT_EXISTS")
            }
        } catch EdgeHostError.automation(let code) {
            print("EDGE_AUTOMATION_OSSTATUS_\(code)")
        } catch let error as EdgeNativeDraftProbe.Unavailable {
            print("NATIVE_AX_UNAVAILABLE_" + error.rawValue)
        } catch NativeMacAXError.accessibility(let code) {
            print("NATIVE_PREFLIGHT_AXERROR_\(code)")
        } catch EdgeHostError.changed { print("NATIVE_EDGE_TARGET_CHANGED") }
          catch EdgeHostError.notFrontmost { print("NATIVE_EDGE_NOT_FRONTMOST") }
          catch EdgeHostError.unsupportedDescriptor { print("NATIVE_EDGE_DESCRIPTOR_UNAVAILABLE") }
          catch NativeMacAXError.targetChanged { print("NATIVE_DRAFT_CHANGED_OR_UNPROVEN") }
          catch { print("CONTROLLED_PREFLIGHT_ERROR"); exit(1) }
    }
}
