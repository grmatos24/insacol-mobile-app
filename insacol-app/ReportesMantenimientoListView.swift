import SwiftUI

@MainActor
@Observable
final class ReportesMantenimientoListViewModel {
    var reportes: [ReporteMantenimientoDto] = []
    var isLoading = false
    var errorMessage: String?

    var filter: APIClient.ReporteFilter = .mesActual
    var search: String = ""
    var fechaInicio: Date? = nil
    var fechaFin: Date? = nil

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listReportes(
                filter: filter,
                searchTerm: search,
                fechaInicio: fechaInicio,
                fechaFin: fechaFin,
                page: 0,
                size: 50
            )
            self.reportes = page.content
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func delete(_ r: ReporteMantenimientoDto) async {
        guard let id = r.id else { return }
        do {
            try await APIClient.shared.deleteReporte(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ReportesMantenimientoListView: View {
    @State private var vm = ReportesMantenimientoListViewModel()
    @State private var showingAdd = false
    @State private var editing: ReporteMantenimientoDto?
    @State private var toDelete: ReporteMantenimientoDto?
    @State private var showingFilters = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filtro", selection: Binding(
                    get: { vm.filter },
                    set: {
                        vm.filter = $0
                        Task { await vm.load() }
                    }
                )) {
                    Text("Mes actual").tag(APIClient.ReporteFilter.mesActual)
                    Text("Próximo mes").tag(APIClient.ReporteFilter.proximoMes)
                    Text("Todos").tag(APIClient.ReporteFilter.todos)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    if vm.isLoading && vm.reportes.isEmpty {
                        ProgressView("Cargando...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if vm.reportes.isEmpty {
                        ContentUnavailableView(
                            "Sin reportes",
                            systemImage: "wrench.and.screwdriver",
                            description: Text("Toca + para crear un reporte de mantenimiento.")
                        )
                    } else {
                        List {
                            ForEach(vm.reportes) { r in
                                ReporteRow(reporte: r)
                                    .contentShape(Rectangle())
                                    .onTapGesture { editing = r }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if r.estado != .facturado {
                                            Button(role: .destructive) {
                                                toDelete = r
                                            } label: {
                                                Label("Eliminar", systemImage: "trash")
                                            }
                                        }
                                        Button {
                                            editing = r
                                        } label: {
                                            Label(r.estado == .facturado ? "Ver" : "Editar",
                                                  systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await vm.load() }
                    }
                }
            }
            .navigationTitle("Mantenimiento")
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .onChange(of: vm.search) { _, _ in
                Task { await vm.load() }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                ReporteMantenimientoFormView(reporte: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { r in
                ReporteMantenimientoFormView(reporte: r) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FiltersSheet(
                    fechaInicio: $vm.fechaInicio,
                    fechaFin: $vm.fechaFin,
                    onApply: { Task { await vm.load() } }
                )
            }
            .alert("¿Eliminar reporte?",
                   isPresented: Binding(
                    get: { toDelete != nil },
                    set: { if !$0 { toDelete = nil } }
                   ),
                   presenting: toDelete) { r in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = r
                    toDelete = nil
                    Task { await vm.delete(target) }
                }
            } message: { _ in
                Text("Esta acción no se puede deshacer.")
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }
}

private struct ReporteRow: View {
    let reporte: ReporteMantenimientoDto

    var cliente: String {
        if let s = reporte.clienteSubEmpresa, !s.isEmpty { return s }
        if let e = reporte.clienteEmpresa, !e.isEmpty { return e }
        return "Cliente #\(reporte.clienteId.map(String.init) ?? "-")"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(cliente)
                        .font(.headline)
                        .lineLimit(1)
                    estadoBadge
                }
                HStack(spacing: 12) {
                    if let f = reporte.fechaServicio?.apiDate {
                        Label(f.displayString, systemImage: "calendar")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let f = reporte.fechaProximoServicio?.apiDate {
                        Label("Próx \(f.displayString)", systemImage: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let n = reporte.detalles?.count, n > 0 {
                    Label("\(n) extintor\(n == 1 ? "" : "es")",
                          systemImage: "flame")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var estadoBadge: some View {
        let isFacturado = reporte.estado == .facturado
        let color: Color = isFacturado ? .green : .orange
        Text(isFacturado ? "FACTURADO" : "BORRADOR")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Filters sheet

private struct FiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fechaInicio: Date?
    @Binding var fechaFin: Date?
    let onApply: () -> Void

    @State private var useInicio: Bool = false
    @State private var useFin: Bool = false
    @State private var localInicio: Date = Date()
    @State private var localFin: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Rango de fechas") {
                    Toggle("Desde", isOn: $useInicio)
                    if useInicio {
                        DatePicker("Fecha inicio", selection: $localInicio,
                                   displayedComponents: .date)
                    }
                    Toggle("Hasta", isOn: $useFin)
                    if useFin {
                        DatePicker("Fecha fin", selection: $localFin,
                                   displayedComponents: .date)
                    }
                }
                Section {
                    Button("Limpiar filtros") {
                        useInicio = false
                        useFin = false
                        fechaInicio = nil
                        fechaFin = nil
                    }
                }
            }
            .navigationTitle("Filtros")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        fechaInicio = useInicio ? localInicio : nil
                        fechaFin = useFin ? localFin : nil
                        onApply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                useInicio = fechaInicio != nil
                useFin = fechaFin != nil
                if let f = fechaInicio { localInicio = f }
                if let f = fechaFin { localFin = f }
            }
        }
    }
}
