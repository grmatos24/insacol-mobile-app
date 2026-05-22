import SwiftUI

@MainActor
@Observable
final class ClientesListViewModel {
    var clientes: [ClienteDto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""

    var filtered: [ClienteDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return clientes }
        return clientes.filter {
            ($0.empresa?.lowercased().contains(q) ?? false)
            || ($0.subEmpresa?.lowercased().contains(q) ?? false)
            || ($0.ruc?.lowercased().contains(q) ?? false)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listClientes(size: 500)
            self.clientes = page.content.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ c: ClienteDto) async {
        guard let id = c.id else { return }
        do {
            try await APIClient.shared.deleteCliente(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ClientesListView: View {
    @State private var vm = ClientesListViewModel()
    @State private var showingAdd = false
    @State private var editing: ClienteDto?
    @State private var toDelete: ClienteDto?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                contentView
            }
            .navigationTitle("Clientes")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.navy)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Nuevo cliente")
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                ClienteFormView(cliente: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { c in
                ClienteFormView(cliente: c) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .alert("¿Eliminar cliente?",
                   isPresented: Binding(
                    get: { toDelete != nil },
                    set: { if !$0 { toDelete = nil } }
                   ),
                   presenting: toDelete) { c in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = c
                    toDelete = nil
                    Task { await vm.delete(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading && vm.clientes.isEmpty {
            ProgressView("Cargando...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.filtered.isEmpty {
            ContentUnavailableView(
                "Sin clientes",
                systemImage: "person.2.slash",
                description: Text(vm.search.isEmpty
                    ? "Toca + para agregar el primer cliente."
                    : "No hay resultados para \"\(vm.search)\".")
            )
        } else {
            List {
                ForEach(vm.filtered) { c in
                    ClienteRow(cliente: c)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = c }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { toDelete = c } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            Button { editing = c } label: {
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

private struct ClienteRow: View {
    let cliente: ClienteDto

    var body: some View {
        BrandCard(padding: 14, radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(cliente.displayName)
                        .font(.headline)
                        .foregroundStyle(Theme.navyText)
                        .lineLimit(1)
                    Spacer()
                    if cliente.rucValidadoHka == true {
                        Label("DGI", systemImage: "checkmark.seal.fill")
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.success.opacity(0.15))
                            .foregroundStyle(Theme.success)
                            .clipShape(Capsule())
                    }
                }

                dottedDivider

                HStack(spacing: 8) {
                    if let r = cliente.ruc, !r.isEmpty {
                        Text("RUC \(r)\(cliente.dv != nil ? " DV \(cliente.dv!)" : "")")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                    Spacer()
                    if let t = cliente.tipoContribuyente, !t.isEmpty {
                        Text(t == "1" ? "Natural" : t == "2" ? "Jurídica" : t)
                            .font(.caption2.bold())
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Theme.info.opacity(0.12))
                            .foregroundStyle(Theme.info)
                            .clipShape(Capsule())
                    }
                }
            }
        }
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
    ClientesListView()
}
