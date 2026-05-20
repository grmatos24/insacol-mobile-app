import SwiftUI

@MainActor
@Observable
final class ReportesMantenimientoListViewModel {
    var reportes: [ReporteMantenimientoDto] = []
    var clientesById: [Int64: ClienteDto] = [:]
    var isLoading = false
    var errorMessage: String?

    var filter: APIClient.ReporteFilter = .mesActual
    var search: String = ""
    var fechaInicio: Date? = nil
    var fechaFin: Date? = nil

    /// Si el usuario no fijó fechas en el sheet de filtros, devolvemos el rango
    /// apropiado para el tab seleccionado.
    private func effectiveDateRange() -> (Date, Date) {
        if let i = fechaInicio, let f = fechaFin { return (i, f) }
        let cal = Calendar.current
        let now = Date()
        switch filter {
        case .mesActual, .proximoMes:
            // Mes actual completo (1er día → último día del mes)
            let comps = cal.dateComponents([.year, .month], from: now)
            let inicio = cal.date(from: comps) ?? now
            let nextMonth = cal.date(byAdding: .month, value: 1, to: inicio) ?? now
            let fin = cal.date(byAdding: .day, value: -1, to: nextMonth) ?? now
            return (inicio, fin)
        case .todos:
            // Rango muy amplio para traer todo
            let inicio = cal.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? now
            let fin = cal.date(from: DateComponents(year: 2099, month: 12, day: 31)) ?? now
            return (inicio, fin)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let (inicio, fin) = effectiveDateRange()
        do {
            async let reportesTask = APIClient.shared.listReportes(
                filter: filter,
                searchTerm: search,
                fechaInicio: inicio,
                fechaFin: fin,
                page: 0,
                size: 100
            )
            // Solo cargamos clientes si todavía no los tenemos (cache simple)
            if clientesById.isEmpty {
                async let clientesTask = APIClient.shared.listClientes(size: 500)
                let (page, cPage) = try await (reportesTask, clientesTask)
                self.reportes = page.content
                var map: [Int64: ClienteDto] = [:]
                for c in cPage.content { if let id = c.id { map[id] = c } }
                self.clientesById = map
            } else {
                self.reportes = try await reportesTask.content
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func displayName(for reporte: ReporteMantenimientoDto) -> String {
        if let id = reporte.clienteId, let c = clientesById[id] {
            if let s = c.subEmpresa, !s.isEmpty { return s }
            if let e = c.empresa, !e.isEmpty { return e }
        }
        if let s = reporte.clienteSubEmpresa, !s.isEmpty { return s }
        if let e = reporte.clienteEmpresa, !e.isEmpty { return e }
        return "Cliente #\(reporte.clienteId.map(String.init) ?? "-")"
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
    @State private var cloningFrom: ReporteMantenimientoDto?
    @State private var iniciandoMantenimientoId: Int64?
    @State private var descargandoPdfId: Int64?
    @State private var pdfToShare: PDFShareItem?
    @State private var generandoFacturaId: Int64?
    @State private var preFacturaItem: PreFacturaItem?

    struct PreFacturaItem: Identifiable {
        let id = UUID()
        let dto: FacturaDto
        let reporteId: Int64
    }

    private func descargarPdf(_ r: ReporteMantenimientoDto) async {
        guard let id = r.id else { return }
        descargandoPdfId = id
        defer { descargandoPdfId = nil }
        do {
            let data = try await APIClient.shared.downloadReportePdf(id: id)
            pdfToShare = PDFShareItem(
                data: data,
                id: id,
                suggestedName: reportePdfFilename(clienteName: vm.displayName(for: r))
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func isFromPreviousYear(_ r: ReporteMantenimientoDto) -> Bool {
        guard let d = r.fechaServicio?.apiDate else { return false }
        let y = Calendar.current.component(.year, from: d)
        let nowY = Calendar.current.component(.year, from: Date())
        return y < nowY
    }

    private func generarPreFactura(_ r: ReporteMantenimientoDto) async {
        guard let id = r.id else { return }
        generandoFacturaId = id
        defer { generandoFacturaId = nil }
        do {
            let dto = try await APIClient.shared.getPreFactura(reporteId: id)
            preFacturaItem = PreFacturaItem(dto: dto, reporteId: id)
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func iniciarMantenimiento(_ r: ReporteMantenimientoDto) async {
        guard let id = r.id else { return }
        iniciandoMantenimientoId = id
        defer { iniciandoMantenimientoId = nil }
        do {
            // Cargamos el reporte completo (con detalles) para clonarlo
            let full = try await APIClient.shared.getReporte(id: id)
            cloningFrom = full
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

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
                    Text("Programados").tag(APIClient.ReporteFilter.proximoMes)
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
                                ReporteRow(reporte: r, clienteName: vm.displayName(for: r))
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
                                            if r.estado == .facturado {
                                                Label("Ver", systemImage: "eye")
                                            } else {
                                                Label("Editar", systemImage: "pencil")
                                            }
                                        }
                                        .tint(.blue)
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if r.estado != .facturado {
                                            Button {
                                                Task { await generarPreFactura(r) }
                                            } label: {
                                                if generandoFacturaId == r.id {
                                                    ProgressView()
                                                } else {
                                                    Label("Crear factura",
                                                          systemImage: "doc.text.fill")
                                                }
                                            }
                                            .tint(.green)
                                        }
                                        if isFromPreviousYear(r) {
                                            Button {
                                                Task { await iniciarMantenimiento(r) }
                                            } label: {
                                                if iniciandoMantenimientoId == r.id {
                                                    ProgressView()
                                                } else {
                                                    Label("Iniciar mantenimiento",
                                                          systemImage: "wrench.adjustable")
                                                }
                                            }
                                            .tint(.green)
                                        }
                                        Button {
                                            Task { await descargarPdf(r) }
                                        } label: {
                                            if descargandoPdfId == r.id {
                                                ProgressView()
                                            } else {
                                                Label("Descargar PDF",
                                                      systemImage: "square.and.arrow.down")
                                            }
                                        }
                                        .tint(.indigo)
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
                ToolbarItem(placement: .topBarLeading) {
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
            .sheet(item: $cloningFrom) { r in
                ReporteMantenimientoFormView(reporte: nil, cloneFrom: r) { saved in
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
            .sheet(item: $pdfToShare) { item in
                PDFShareSheet(
                    data: item.data,
                    suggestedName: item.suggestedName ?? "Reporte.pdf"
                )
            }
            .sheet(item: $preFacturaItem) { item in
                FacturaFormView(
                    prefilledDto: item.dto,
                    reporteMantenimientoId: item.reporteId
                ) { saved in
                    preFacturaItem = nil
                    if saved { Task { await vm.load() } }
                }
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
    let clienteName: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(clienteName)
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
