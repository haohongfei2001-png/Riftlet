import RiftletCore
import RiftletAdapters

/// Composition for the explicit, separate generated-image Web acceptance mode.
/// Round-five v11 evidence admits visual start here only; neither production
/// screenshots nor terminal failure/safe retry have been admitted.
enum WebAcceptanceConfiguration {
    static let receiptPolicy = ReceiptPolicy(
        syntheticAcceptanceProfiles: [ChatGPTWebPageProgram.acceptanceProfile.profileID: .webChat],
        syntheticUploadStartProfiles: [ChatGPTWebPageProgram.acceptanceUploadStartProfileID: .webChat])
}
