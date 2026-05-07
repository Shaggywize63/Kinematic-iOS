// Campaigns feature was removed; this file remains as an empty stub so that
// stale local copies (Xcode's filesystem-synchronized group picks them up
// automatically) still compile. Safe to delete once every clone has pulled.

import Foundation
import Combine

@MainActor
final class CampaignsViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
}
