import SwiftUI

struct MainTabView: View {
    private var canSeeGastos: Bool {
        let role = AuthManager.shared.role?.lowercased() ?? ""
        return role == "developer" || role == "admin"
    }

    var body: some View {
        TabView {
            ComercialView()
                .tabItem {
                    Label("Comercial", systemImage: "doc.text")
                }

            ReportesMantenimientoListView()
                .tabItem {
                    Label("Mantenimiento", systemImage: "wrench.and.screwdriver")
                }

            if canSeeGastos {
                GastosListView()
                    .tabItem {
                        Label("Gastos", systemImage: "creditcard")
                    }
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
            ZStack {
                Theme.surface.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        userCard
                        aparienciaCard
                        servidorCard
                        logoutButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Cards

    private var userCard: some View {
        BrandCard(padding: 16, radius: 18) {
            HStack(spacing: 14) {
                // Avatar con iniciales
                ZStack {
                    Circle()
                        .fill(Theme.navy)
                        .frame(width: 52, height: 52)
                    Text(initials)
                        .font(.headline.bold())
                        .foregroundStyle(Theme.amber)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(auth.name ?? auth.username ?? "—")
                        .font(.headline)
                        .foregroundStyle(Theme.navyText)
                    HStack(spacing: 6) {
                        if let u = auth.username {
                            Text(u)
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                        }
                        if let r = auth.role {
                            StatusBadge(text: r.uppercased(), color: Theme.amberDark)
                        }
                    }
                }
                Spacer()
            }
        }
    }

    private var aparienciaCard: some View {
        BrandCard(padding: 16, radius: 18) {
            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(text: "Apariencia")
                Picker("Tema", selection: $appearanceModeRaw) {
                    ForEach(AppearanceMode.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    private var servidorCard: some View {
        BrandCard(padding: 16, radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Servidor")
                dottedDivider
                HStack {
                    Image(systemName: "server.rack")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    Text(APIClient.shared.baseURL.absoluteString)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
            }
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive) {
            AuthManager.shared.clear()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.headline)
                Text("Cerrar sesión")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Theme.danger.opacity(0.12))
            .foregroundStyle(Theme.danger)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    // MARK: - Helpers

    private var initials: String {
        let name = auth.name ?? auth.username ?? ""
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }

    private var dottedDivider: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: g.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundColor(Theme.divider)
        }
        .frame(height: 1)
    }
}

#Preview {
    MainTabView()
}
