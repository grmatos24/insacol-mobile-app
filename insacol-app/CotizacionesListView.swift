import SwiftUI

struct CotizacionesListView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView("Cotizaciones", systemImage: "doc.plaintext")
                .navigationTitle("Cotizaciones")
        }
    }
}
