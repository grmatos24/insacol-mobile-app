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
            Group {
                if vm.isLoading && vm.gastos.isEmpty {
                    ProgressView("Cargando...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.gastos.isEmpty {
                    ContentUnavailableView(
                        "Sin gastos",
                        systemImage: "tray",
                        description: Text("Toca el botón + para registrar tu primer gasto.")
                    )
                } else {
                    List {
                        ForEach(vm.gastos) { gasto in
                            GastoRow(gasto: gasto)
                                .contentShape(Rectangle())
                                .onTapGesture { editingGasto = gasto }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !(gasto.anulado ?? false) {
                                        Button(role: .destructive) {
                                            gastoToAnular = gasto
                                        } label: {
                                            Label("Anular", systemImage: "xmark.circle")
                                        }
                                    }
                                    Button {
                                        editingGasto = gasto
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Gastos")
            .searchable(text: $vm.searchTerm, prompt: "Buscar...")
            .onChange(of: vm.searchTerm) { _, _ in
                Task { await vm.load() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
}

private struct GastoRow: View {
    let gasto: GastoDto

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(gasto.proveedor ?? "Sin proveedor")
                        .font(.headline)
                        .lineLimit(1)
                    if gasto.anulado == true {
                        Text("ANULADO")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    }
                }
                Text(gasto.categoriaNombre ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let f = gasto.fechaGasto?.apiDate {
                        Label(f.displayString, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let m = gasto.metodoPago {
                        Label(m.capitalized, systemImage: "creditcard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMoney(gasto.total ?? 0))
                    .font(.headline)
                if let imp = gasto.impuestos, imp > 0 {
                    Text("ITBMS \(formatMoney(imp))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(gasto.anulado == true ? 0.5 : 1.0)
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
