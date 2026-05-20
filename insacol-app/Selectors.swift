import SwiftUI

// MARK: - Cliente Selector

struct ClienteSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientes: [ClienteDto] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNuevoCliente = false
    @State private var createdCliente: ClienteDto?

    let onPick: (ClienteDto) -> Void

    var filtered: [ClienteDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return clientes }
        return clientes.filter { c in
            (c.empresa?.lowercased().contains(q) ?? false)
            || (c.subEmpresa?.lowercased().contains(q) ?? false)
            || (c.ruc?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && clientes.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView("Sin clientes", systemImage: "person.2.slash")
                } else {
                    List(filtered) { c in
                        Button {
                            onPick(c)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let r = c.ruc, !r.isEmpty {
                                    Text("RUC \(r)\(c.dv != nil ? " DV \(c.dv!)" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar cliente")
            .navigationTitle("Seleccionar cliente")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNuevoCliente = true
                    } label: {
                        Label("Nuevo cliente", systemImage: "plus")
                    }
                }
            }
            .onChange(of: createdCliente) { _, new in
                guard let c = new else { return }
                onPick(c)
                dismiss()
            }
            .sheet(isPresented: $showingNuevoCliente) {
                ClienteFormView(cliente: nil) { saved in
                    if saved {
                        Task {
                            do {
                                let page = try await APIClient.shared.listClientes(size: 500)
                                // Pick the one with the highest ID (most recently created)
                                let newest = page.content.max(by: { ($0.id ?? 0) < ($1.id ?? 0) })
                                if let c = newest {
                                    createdCliente = c
                                }
                            } catch {}
                        }
                    }
                }
            }
            .task {
                if clientes.isEmpty {
                    isLoading = true
                    defer { isLoading = false }
                    do {
                        let page = try await APIClient.shared.listClientes(size: 500)
                        clientes = page.content.sorted {
                            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

// MARK: - Extintor Catálogo Picker

/// Picker que muestra el catálogo completo de extintores (marca/tipo/capacidad).
/// Se usa para cambiar el tipo de un extintor ya agregado a un reporte.
struct ExtintorCatalogoPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (ExtintorDto, String) -> Void   // (extintor, displayName)

    @State private var cache = CatalogCache.shared
    @State private var search: String = ""
    @State private var isLoading = false

    var filtered: [ExtintorDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let sorted = cache.extintores.sorted {
            cache.displayName(for: $0).localizedCaseInsensitiveCompare(cache.displayName(for: $1)) == .orderedAscending
        }
        guard !q.isEmpty else { return sorted }
        return sorted.filter { ext in
            cache.displayName(for: ext).lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && cache.extintores.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView("Sin coincidencias", systemImage: "flame.slash")
                } else {
                    List(filtered) { ext in
                        Button {
                            onPick(ext, cache.displayName(for: ext))
                            dismiss()
                        } label: {
                            Text(cache.displayName(for: ext))
                                .foregroundStyle(.primary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar marca, tipo o capacidad")
            .navigationTitle("Cambiar tipo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task {
                isLoading = true
                await cache.loadIfNeeded()
                isLoading = false
            }
        }
    }
}

// MARK: - Extintor Cliente Picker

struct ExtintorClientePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let clienteId: Int64
    let excludeIds: Set<Int64>
    let onPick: (ExtintorClienteDto) -> Void

    @State private var extintores: [ExtintorClienteDto] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var filtered: [ExtintorClienteDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        let base = extintores
            .filter { e in
                guard let id = e.id else { return true }
                return !excludeIds.contains(id)
            }
            .sorted { a, b in
                (a.codigoInsacol ?? "").localizedStandardCompare(b.codigoInsacol ?? "") == .orderedAscending
            }
        if q.isEmpty { return base }
        return base.filter { e in
            (e.extintorNombre?.lowercased().contains(q) ?? false)
            || (e.numeroSerie?.lowercased().contains(q) ?? false)
            || (e.codigoInsacol?.lowercased().contains(q) ?? false)
            || (e.ubicacionHabitual?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && extintores.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "Sin extintores disponibles",
                        systemImage: "flame.slash",
                        description: Text(excludeIds.isEmpty
                            ? "Este cliente no tiene extintores activos."
                            : "Todos los extintores ya fueron agregados al reporte.")
                    )
                } else {
                    List(filtered) { e in
                        Button {
                            onPick(e)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(e.extintorNombre ?? "Extintor")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if let s = e.numeroSerie {
                                        Label(s, systemImage: "barcode")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if let c = e.codigoInsacol {
                                        Label(c, systemImage: "number")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if let u = e.ubicacionHabitual, !u.isEmpty {
                                    Label(u, systemImage: "mappin.and.ellipse")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar por serie, código o ubicación")
            .navigationTitle("Agregar extintor")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task {
                if extintores.isEmpty {
                    isLoading = true
                    defer { isLoading = false }
                    do {
                        extintores = try await APIClient.shared.listExtintoresActivos(clienteId: clienteId)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}

// MARK: - Producto Selector

struct ProductoSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var resultados: [ProductoDto] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    let onPick: (ProductoDto) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if resultados.isEmpty && !search.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "magnifyingglass",
                        description: Text("No se encontraron productos para \"\(search)\".")
                    )
                } else if resultados.isEmpty {
                    ContentUnavailableView(
                        "Buscar producto",
                        systemImage: "shippingbox",
                        description: Text("Escribe el nombre del producto.")
                    )
                } else {
                    List(resultados) { p in
                        Button {
                            onPick(p)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.nombre ?? "Producto").font(.headline).foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if let tipo = p.tipoProducto {
                                        Text(tipo == "SERVICIO" ? "Servicio" : "Producto")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.15))
                                            .foregroundStyle(.purple)
                                            .clipShape(Capsule())
                                    }
                                    if let precio = p.precio {
                                        Text(precio.currencyString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar producto")
            .onChange(of: search) { _, q in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await runSearch(q)
                }
            }
            .navigationTitle("Seleccionar producto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func runSearch(_ term: String) async {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else {
            resultados = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            resultados = try await APIClient.shared.searchProductos(term: term)
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }
}
