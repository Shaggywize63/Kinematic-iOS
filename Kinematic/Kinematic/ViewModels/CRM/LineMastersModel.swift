import Foundation
import Combine

/// The Make and Brand pick lists for deal lines (connected-B2B). Loaded once per screen; a failed
/// fetch leaves the list empty so the pickers simply offer "None".
@MainActor
final class LineMastersModel: ObservableObject {
    @Published private(set) var makes: [ProductMake] = []
    @Published private(set) var brands: [ProductBrand] = []
    @Published private(set) var didLoad = false

    func load() async {
        if didLoad { return }
        async let makeRows: [ProductMake] = (try? await CRMService.shared.listMakes()) ?? []
        async let brandRows: [ProductBrand] = (try? await CRMService.shared.listBrands()) ?? []
        let loadedMakes = await makeRows
        let loadedBrands = await brandRows
        makes = loadedMakes
        brands = loadedBrands
        didLoad = true
    }
}
