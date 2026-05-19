import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            GastosListView()
                .tabItem {
                    Label("Gastos", systemImage: "creditcard")
                }

            CategoriasListView()
                .tabItem {
                    Label("Categorías", systemImage: "list.bullet.rectangle")
                }

            AjustesView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape")
                }
        }
    }
}

struct AjustesView: View {
    @State private var auth = AuthManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Sesión") {
                    LabeledContent("Usuario", value: auth.username ?? "—")
                    LabeledContent("Nombre", value: auth.name ?? "—")
                    LabeledContent("Rol", value: auth.role ?? "—")
                }
                Section("Servidor") {
                    LabeledContent("URL", value: APIClient.shared.baseURL.absoluteString)
                }
                Section {
                    Button(role: .destructive) {
                        AuthManager.shared.clear()
                    } label: {
                        Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

#Preview {
    MainTabView()
}
