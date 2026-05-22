import SwiftUI

@MainActor
@Observable
final class GastosListViewModel {
    var gastos: [GastoDto] = []
    var isLoading = false
    var errorMessage: String?
    var searchTerm: String = ""

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listGastos(term: searchTerm, page: 0, size: 50)
            self.gastos = page.content
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func anular(_ gasto: GastoDto) async {
        guard let id = gasto.id else { return }
        do {
            _ = try await APIClient.shared.anularGasto(id: id)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

struct GastosListView: View {
    @State private var vm = GastosListViewModel()
    @State private var showingAdd = false
    @State private var editingGasto: GastoDto?
    @State private var gastoToAnular: GastoDto?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                contentView
            }
            .navigationTitle("Gastos")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.searchTerm, prompt: "Buscar...")
            .onChange(of: vm.searchTerm) { _, _ in
                Task { await vm.load() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(Theme.navy)
                            .frame(width: 32, height: 32)
                            .background(Theme.amber)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Nuevo gasto")
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                GastoFormView(gasto: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editingGasto) { gasto in
                GastoFormView(gasto: gasto) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .alert("¿Anular gasto?",
                   isPresented: Binding(
                    get: { gastoToAnular != nil },
                    set: { if !$0 { gastoToAnular = nil } }
                   ),
                   presenting: gastoToAnular) { gasto in
                Button("Cancelar", role: .cancel) { gastoToAnular = nil }
                Button("Anular", role: .destructive) {
                    let g = gasto
                    gastoToAnular = nil
                    Task { await vm.anular(g) }
                }
            } message: { gasto in
                Text("Se marcará como anulado el gasto de \(formatMoney(gasto.total ?? 0)).")
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   ),
                   actions: {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading && vm.gastos.isEmpty {
            ProgressView("Cargando...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.gastos.isEmpty {
            ContentUnavailableView(
                "Sin gastos",
                systemImage: "tray",
                description: Text("Toca + para registrar tu primer gasto.")
            )
        } else {
            List {
                ForEach(vm.gastos) { gasto in
                    GastoRow(gasto: gasto)
                        .contentShape(Rectangle())
                        .onTapGesture { editingGasto = gasto }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if !(gasto.anulado ?? false) {
                                Button(role: .destructive) {
                                    gastoToAnular = gasto
                                } label: {
                                    Label("Anular", systemImage: "xmark.circle")
                                }
                            }
                            Button { editingGasto = gasto } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
        }
    }
}

private struct GastoRow: View {
    let gasto: GastoDto

    var body: some View {
        BrandCard(padding: 14, radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(gasto.proveedor ?? "Sin proveedor")
                            .font(.headline)
                            .foregroundStyle(Theme.navyText)
                            .lineLimit(1)
                        Text(gasto.categoriaNombre ?? "—")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    if gasto.anulado == true {
                        StatusBadge(text: "ANULADO", color: Theme.danger)
                    }
                }

                dottedDivider

                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 10) {
                            if let f = gasto.fechaGasto?.apiDate {
                                Label(f.displayString, systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            if let m = gasto.metodoPago {
                                Label(m.capitalized, systemImage: "creditcard")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        if gasto.esFondosPersonales == true {
                            Label("Fondos personales · \(gasto.acreedorNombre ?? "—")",
                                  systemImage: "person.crop.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                        } else if let cb = gasto.cuentaBancariaNombre, !cb.isEmpty {
                            Label(cb, systemImage: "building.columns")
                                .font(.caption)
                                .foregroundStyle(Theme.info)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatMoney(gasto.total ?? 0))
                            .font(.headline.bold())
                            .foregroundStyle(Theme.amberDark)
                        if let imp = gasto.impuestos, imp > 0 {
                            Text("ITBMS \(formatMoney(imp))")
                                .font(.caption2)
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
        }
        .opacity(gasto.anulado == true ? 0.5 : 1.0)
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

func formatMoney(_ value: Decimal) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.locale = Locale(identifier: "es_PA")
    f.currencyCode = "USD"
    return f.string(from: value as NSDecimalNumber) ?? "\(value)"
}

#Preview {
    GastosListView()
}
