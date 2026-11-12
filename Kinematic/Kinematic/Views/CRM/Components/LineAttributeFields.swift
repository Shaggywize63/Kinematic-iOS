import SwiftUI

/// Make, Brand, Order value and MAC funnel reference for one deal line (connected-B2B). Shared by the
/// deal create form's line editor and the deal detail's line editor. The make / brand lists come from
/// `LineMastersModel`; both pickers offer "None". The funnel reference is required (marker + inline
/// message) when the brand is MAC.
struct LineAttributeFields: View {
    @Binding var makeId: String?
    @Binding var makeName: String?
    @Binding var brandId: String?
    @Binding var brandName: String?
    @Binding var orderValueText: String
    @Binding var funnelRef: String
    let makes: [ProductMake]
    let brands: [ProductBrand]
    /// False for an untouched blank row, which is dropped on save and so needs no message.
    var validate: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            optionPicker(title: "Make", id: $makeId, name: $makeName, options: makes)
            optionPicker(title: "Brand", id: $brandId, name: $brandName, options: brands)
            HStack(spacing: 8) {
                Text("Order value (\u{20B9})")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Optional", text: $orderValueText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
            }
            if validate && !DealLineRules.orderValueTextIsValid(orderValueText) {
                Text(DealLineRules.invalidOrderValueMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
            HStack(spacing: 6) {
                TextField("MAC funnel reference", text: $funnelRef)
                    .textFieldStyle(.roundedBorder)
                if DealLineRules.isMacBrand(brandName) {
                    Text("*")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.red)
                        .accessibilityLabel("Required")
                }
            }
            if validate, let message = DealLineRules.funnelProblem(brandName: brandName, funnelRef: funnelRef) {
                Text(message)
                    .font(.footnote)
                    .foregroundColor(.red)
            }
        }
    }

    /// A menu picker over `options` plus "None". Picking sets the id and the name together; a value
    /// that is not in the (active) list, such as an inactive make on a saved line, stays selectable.
    private func optionPicker(
        title: String,
        id: Binding<String?>,
        name: Binding<String?>,
        options: [LineOption]
    ) -> some View {
        let selection = Binding<String>(
            get: { id.wrappedValue ?? "" },
            set: { newId in
                if newId.isEmpty {
                    id.wrappedValue = nil
                    name.wrappedValue = nil
                } else {
                    id.wrappedValue = newId
                    name.wrappedValue = options.first(where: { $0.id == newId })?.name ?? name.wrappedValue
                }
            }
        )
        let current = id.wrappedValue ?? ""
        let currentIsListed = options.contains(where: { $0.id == current })
        return Picker(title, selection: selection) {
            Text("None").tag("")
            if !current.isEmpty && !currentIsListed {
                Text(name.wrappedValue ?? "Current").tag(current)
            }
            ForEach(options) { option in
                Text(option.name).tag(option.id)
            }
        }
        .pickerStyle(.menu)
    }
}
