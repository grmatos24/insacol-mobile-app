import SwiftUI

struct FacturasListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Facturas", systemImage: "doc.text")
                .navigationTitle("Facturas")
        }
    }
}
