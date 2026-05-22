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
    @State private var selectedTipoId: Int64? = nil
    @State private var selectedCapacidadId: Int64? = nil

    var filtered: [ExtintorDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        return cache.extintores
            .filter { ext in
                if let t = selectedTipoId, ext.tipoId != t { return false }
                if let c = selectedCapacidadId, ext.capacidadId != c { return false }
                if q.isEmpty { return true }
                return cache.displayName(for: ext).lowercased().contains(q)
            }
            .sorted {
                cache.displayName(for: $0).localizedCaseInsensitiveCompare(cache.displayName(for: $1)) == .orderedAscending
            }
    }

    private var availableTipos: [(Int64, String)] {
        let ids = Set(cache.extintores.compactMap(\.tipoId))
        return ids.compactMap { id in cache.tipos[id].map { (id, $0) } }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    private var availableCapacidades: [(Int64, String)] {
        let ids = Set(cache.extintores.filter { selectedTipoId == nil || $0.tipoId == selectedTipoId }.compactMap(\.capacidadId))
        return ids.compactMap { id in cache.capacidades[id].map { (id, $0) } }
            .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !cache.extintores.isEmpty {
                    filterChips
                }
                Group {
                    if isLoading && cache.extintores.isEmpty {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filtered.isEmpty {
                        ContentUnavailableView("Sin coincidencias", systemImage: "flame.slash")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var filterChips: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableTipos, id: \.0) { id, nombre in
                        FilterChip(
                            label: nombre,
                            isSelected: selectedTipoId == id,
                            action: {
                                if selectedTipoId == id {
                                    selectedTipoId = nil
                                } else {
                                    selectedTipoId = id
                                    if let current = selectedCapacidadId,
                                       !availableCapacidades.contains(where: { $0.0 == current }) {
                                        selectedCapacidadId = nil
                                    }
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            if !availableCapacidades.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(availableCapacidades, id: \.0) { id, label in
                            FilterChip(
                                label: label,
                                isSelected: selectedCapacidadId == id,
                                action: { selectedCapacidadId = selectedCapacidadId == id ? nil : id }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            Divider()
        }
    }
}

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Theme.navy : Color.black.opacity(0.06))
                .foregroundStyle(isSelected ? Color.white : Theme.navyText)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
    @State private var productos: [ProductoDto] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    let onPick: (ProductoDto) -> Void

    var filtered: [ProductoDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return productos }
        return productos.filter { p in
            (p.nombre?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && productos.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "Sin productos" : "Sin resultados",
                        systemImage: "shippingbox",
                        description: search.isEmpty ? nil : Text("No se encontraron productos para \"\(search)\".")
                    )
                } else {
                    List(filtered) { p in
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
            .navigationTitle("Seleccionar producto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .task {
                guard productos.isEmpty else { return }
                isLoading = true
                defer { isLoading = false }
                do {
                    let page = try await APIClient.shared.listProductos(size: 500)
                    productos = page.content.sorted {
                        ($0.nombre ?? "").localizedCaseInsensitiveCompare($1.nombre ?? "") == .orderedAscending
                    }
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }
}
