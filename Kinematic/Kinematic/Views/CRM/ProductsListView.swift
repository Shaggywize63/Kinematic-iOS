import SwiftUI

struct ProductsListView: View {
    @State private var products: [Product] = []
    @State private var loading = true
    @State private var search = ""

    var body: some View {
        List {
            ForEach(filtered) { p in
                ProductRow(product: p)
            }
        }
        .listStyle(.plain)
        .navigationTitle("Products")
        .searchable(text: $search, prompt: "Search products")
        .overlay {
            if loading {
                ProgressView()
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No products",
                    systemImage: "shippingbox",
                    description: Text(search.isEmpty
                                      ? "Add products in the dashboard or via the API."
                                      : "No matches for “\(search)”.")
                )
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var filtered: [Product] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return products }
        return products.filter {
            $0.name.lowercased().contains(q)
                || ($0.sku?.lowercased().contains(q) ?? false)
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        products = (try? await CRMService.shared.listProducts()) ?? []
    }
}

private struct ProductRow: View {
    let product: Product
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(uiColor: .tertiarySystemBackground))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "shippingbox.fill")
                        .foregroundColor(.indigo)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(product.name)
                    .font(.system(size: 14, weight: .bold))
                if let sku = product.sku {
                    Text("SKU: \(sku)").font(.caption2).foregroundColor(.secondary)
                }
                if let hsn = product.hsnCode {
                    Text("HSN: \(hsn)").font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(CurrencyFormatter.formatINR(product.unitPrice))
                    .font(.system(size: 13, weight: .heavy))
                if let tax = product.taxPct, tax > 0 {
                    Text("+ \(Int(tax))% GST").font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
