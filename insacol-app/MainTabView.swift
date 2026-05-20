import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            ReportesMantenimientoListView()
                .tabItem {
                    Label("Mantenimiento", systemImage: "wrench.and.screwdriver")
                }

            ComercialView()
                .tabItem {
                    Label("Comercial", systemImage: "doc.text")
                }

            GastosListView()
                .tabItem {
                    Label("Gastos", systemImage: "creditcard")
                }

            CatalogosView()
                .tabItem {
                    Label("Catálogos", systemImage: "books.vertical")
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
    @AppStorage("appearanceMode") private var appearanceModeRaw: String = AppearanceMode.system.rawValue

    var body: some View {
        NavigationStack {
            List {
                Section("Sesión") {
                    LabeledContent("Usuario", value: auth.username ?? "—")
                    LabeledContent("Nombre", value: auth.name ?? "—")
                    LabeledContent("Rol", value: auth.role ?? "—")
                }
                Section("Apariencia") {
                    Picker("Tema", selection: $appearanceModeRaw) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.label).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
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
