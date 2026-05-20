import SwiftUI

@MainActor
@Observable
final class ProductosListViewModel {
    var productos: [ProductoDto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            if search.trimmingCharacters(in: .whitespaces).isEmpty {
                let page = try await APIClient.shared.listProductos(page: 0, size: 50)
                self.productos = page.content
            } else {
                self.productos = try await APIClient.shared.searchProductos(term: search)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ p: ProductoDto) async {
        guard let id = p.id else { return }
        do {
            try await APIClient.shared.deleteProducto(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProductosListView: View {
    @State private var vm = ProductosListViewModel()
    @State private var showingAdd = false
    @State private var editing: ProductoDto?
    @State private var toDelete: ProductoDto?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.productos.isEmpty {
                    ProgressView("Cargando...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.productos.isEmpty {
                    ContentUnavailableView(
                        "Sin productos",
                        systemImage: "shippingbox",
                        description: Text(vm.search.isEmpty
                            ? "Toca + para agregar el primer producto."
                            : "No hay resultados para \"\(vm.search)\".")
                    )
                } else {
                    List {
                        ForEach(vm.productos) { p in
                            ProductoRow(producto: p)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = p }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        toDelete = p
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                    Button {
                                        editing = p
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
            .navigationTitle("Productos")
            .searchable(text: $vm.search, prompt: "Buscar producto")
            .onChange(of: vm.search) { _, _ in Task { await vm.load() } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                ProductoFormView(producto: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { p in
                ProductoFormView(producto: p) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .alert("¿Eliminar producto?",
                   isPresented: Binding(
                    get: { toDelete != nil },
                    set: { if !$0 { toDelete = nil } }
                   ),
                   presenting: toDelete) { p in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = p
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
}

private struct ProductoRow: View {
    let producto: ProductoDto

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(producto.nombre ?? "Producto").font(.headline)
                if let tipo = producto.tipoProducto {
                    Text(tipo == "SERVICIO" ? "Servicio" : "Producto")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if let precio = producto.precio {
                Text(precio.currencyString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    ProductosListView()
}
