import SwiftUI

struct ProductosListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Productos", systemImage: "shippingbox")
                .navigationTitle("Productos")
        }
    }
}
