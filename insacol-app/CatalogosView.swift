import SwiftUI

private enum CatalogosTab { case clientes, productos, categorias }

struct CatalogosView: View {
    @State private var tab: CatalogosTab = .clientes

    private var canSeeCategorias: Bool {
        let role = AuthManager.shared.role?.lowercased() ?? ""
        return role == "developer" || role == "admin"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Clientes").tag(CatalogosTab.clientes)
                Text("Productos").tag(CatalogosTab.productos)
                if canSeeCategorias {
                    Text("Categorías").tag(CatalogosTab.categorias)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            switch tab {
            case .clientes:
                ClientesListView()
            case .productos:
                ProductosListView()
            case .categorias:
                CategoriasListView()
            }
        }
    }
}
