import SwiftUI

// MARK: - Cliente Selector

struct ClienteSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientes: [ClienteDto] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

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
        let base = extintores.filter { e in
            guard let id = e.id else { return true }
            return !excludeIds.contains(id)
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
