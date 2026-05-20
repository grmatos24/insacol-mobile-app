import SwiftUI

private enum ComercialTab { case facturas, cotizaciones }

struct ComercialView: View {
    @State private var tab: ComercialTab = .facturas

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Facturas").tag(ComercialTab.facturas)
                Text("Cotizaciones").tag(ComercialTab.cotizaciones)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            switch tab {
            case .facturas:
                FacturasListView()
            case .cotizaciones:
                CotizacionesListView()
            }
        }
    }
}
