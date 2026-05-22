import SwiftUI

@MainActor
@Observable
final class FacturasListViewModel {
    var facturas: [FacturaDto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""
    var filtroEstado: FiltroEstado = .todas
    var fechaInicio: Date?
    var fechaFin: Date?

    enum FiltroEstado: String, CaseIterable, Identifiable {
        case todas = "Todas"
        case pendientes = "Pendientes"
        case pagadas = "Pagadas"
        var id: String { rawValue }
        var pagado: Bool? {
            switch self {
            case .todas: nil
            case .pendientes: false
            case .pagadas: true
            }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listFacturas(
                searchTerm: search,
                pagado: filtroEstado.pagado,
                fechaInicio: fechaInicio,
                fechaFin: fechaFin,
                size: 50
            )
            self.facturas = page.content
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func anular(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await APIClient.shared.anularFactura(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emitirFe(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await APIClient.shared.emitirFacturaElectronica(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FacturasListView: View {
    @State private var vm = FacturasListViewModel()
    @State private var showingAdd = false
    @State private var showingFilters = false
    @State private var selectedFactura: FacturaDto?
    @State private var toAnular: FacturaDto?
    @State private var toEmitirFe: FacturaDto?
    @State private var descargandoPdfId: Int64?
    @State private var descargandoFePdfId: Int64?
    @State private var pdfToShare: PDFShareItem?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("Estado", selection: Binding(
                        get: { vm.filtroEstado },
                        set: { vm.filtroEstado = $0; Task { await vm.load() } }
                    )) {
                        ForEach(FacturasListViewModel.FiltroEstado.allCases) { e in
                            Text(e.rawValue).tag(e)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    contentView
                }
            }
            .navigationTitle("Facturas")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .onChange(of: vm.search) { _, _ in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await vm.load()
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
            .navigationDestination(item: $selectedFactura) { f in
                FacturaDetailView(factura: f)
            }
            .sheet(isPresented: $showingAdd) {
                FacturaFormView(prefilledDto: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FacturasFiltersSheet(
                    fechaInicio: $vm.fechaInicio,
                    fechaFin: $vm.fechaFin,
                    onApply: { Task { await vm.load() } }
                )
            }
            .sheet(item: $pdfToShare) { item in
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName ?? "Factura.pdf")
            }
            .alert("¿Anular factura?",
                   isPresented: Binding(
                    get: { toAnular != nil },
                    set: { if !$0 { toAnular = nil } }
                   ),
                   presenting: toAnular) { f in
                Button("Cancelar", role: .cancel) { toAnular = nil }
                Button("Anular", role: .destructive) {
                    let target = f; toAnular = nil
                    Task { await vm.anular(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert(toEmitirFe?.estadoFe == "ERROR" ? "¿Reintentar factura electrónica?" : "¿Emitir factura electrónica?",
                   isPresented: Binding(
                    get: { toEmitirFe != nil },
                    set: { if !$0 { toEmitirFe = nil } }
                   ),
                   presenting: toEmitirFe) { f in
                Button("Cancelar", role: .cancel) { toEmitirFe = nil }
                Button(f.estadoFe == "ERROR" ? "Reintentar" : "Emitir") {
                    let target = f; toEmitirFe = nil
                    Task { await vm.emitirFe(target) }
                }
            } message: { f in
                Text(f.estadoFe == "ERROR"
                    ? "La emisión anterior falló. Se intentará enviar de nuevo a la DGI vía HKA."
                    : "Se enviará la factura a la DGI vía HKA. Asegúrate de que los datos estén correctos.")
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   ),
                   presenting: vm.errorMessage) { _ in
                Button("OK") { vm.errorMessage = nil }
            } message: { msg in Text(msg) }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        Group {
            if vm.isLoading && vm.facturas.isEmpty {
                ProgressView("Cargando...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.facturas.isEmpty {
                ContentUnavailableView(
                    "Sin facturas",
                    systemImage: "doc.text",
                    description: Text("Toca + para crear la primera factura.")
                )
            } else {
                List {
                    ForEach(vm.facturas) { f in
                        FacturaRow(factura: f)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedFactura = f }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                if f.estadoFe == "EMITIDA" {
                                    Button {
                                        Task { await descargarFePdf(f) }
                                    } label: {
                                        if descargandoFePdfId == f.id {
                                            ProgressView()
                                        } else {
                                            Label("PDF FE", systemImage: "checkmark.seal")
                                        }
                                    }
                                    .tint(.teal)
                                } else if f.estadoFe == "ERROR" || f.anulada != true {
                                    Button {
                                        toEmitirFe = f
                                    } label: {
                                        Label(f.estadoFe == "ERROR" ? "Reintentar FE" : "Emitir FE",
                                              systemImage: f.estadoFe == "ERROR" ? "arrow.clockwise.circle" : "bolt.fill")
                                    }
                                    .tint(f.estadoFe == "ERROR" ? .red : .orange)
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if f.pagado != true && f.anulada != true {
                                    Button(role: .destructive) {
                                        toAnular = f
                                    } label: {
                                        Label("Anular", systemImage: "xmark.circle")
                                    }
                                }
                                Button {
                                    Task { await descargarPdf(f) }
                                } label: {
                                    if descargandoPdfId == f.id {
                                        ProgressView()
                                    } else {
                                        Label("PDF", systemImage: "square.and.arrow.down")
                                    }
                                }
                                .tint(.indigo)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await vm.load() }
            }
        }
    }

    private func descargarFePdf(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        descargandoFePdfId = id
        defer { descargandoFePdfId = nil }
        do {
            let data = try await APIClient.shared.downloadFacturaFePdf(id: id)
            pdfToShare = PDFShareItem(
                data: data,
                id: id,
                suggestedName: "FacturaFE_\(f.serie ?? String(id)).pdf"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func descargarPdf(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        descargandoPdfId = id
        defer { descargandoPdfId = nil }
        do {
            let data = try await APIClient.shared.downloadFacturaPdf(id: id)
            pdfToShare = PDFShareItem(
                data: data,
                id: id,
                suggestedName: "Factura_\(f.clienteDisplayName.replacingOccurrences(of: " ", with: "_")).pdf"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

}

// MARK: - Factura Row

private struct FacturaRow: View {
    let factura: FacturaDto

    var body: some View {
        BrandCard(padding: 14, radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(factura.clienteDisplayName)
                            .font(.headline)
                            .foregroundStyle(Theme.navyText)
                            .lineLimit(1)
                        HStack(spacing: 4) {
                            if let s = factura.serie, !s.isEmpty {
                                Text(s).font(.caption).foregroundStyle(Theme.textMuted)
                            }
                            if let f = factura.fecha?.apiDate {
                                Text("· \(f.displayString)").font(.caption).foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                    Spacer()
                    pagoBadge
                }

                dottedDivider

                HStack(spacing: 6) {
                    feBadge
                    Spacer()
                    if let total = factura.total {
                        Text(total.currencyString)
                            .font(.headline.bold())
                            .foregroundStyle(Theme.amberDark)
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

    @ViewBuilder
    private var pagoBadge: some View {
        if factura.anulada == true {
            StatusBadge(text: "ANULADA", color: Theme.danger)
        } else {
            StatusBadge(text: factura.pagado == true ? "PAGADA" : "PENDIENTE",
                        color: factura.pagado == true ? Theme.success : Theme.amberDark)
        }
    }

    @ViewBuilder
    private var feBadge: some View {
        switch factura.estadoFe {
        case "EMITIDA": StatusBadge(text: "FE EMITIDA", color: Theme.info)
        case "ERROR":   StatusBadge(text: "FE ERROR",   color: Theme.danger)
        default:        EmptyView()
        }
    }
}

// MARK: - Filters Sheet

private struct FacturasFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fechaInicio: Date?
    @Binding var fechaFin: Date?
    let onApply: () -> Void

    @State private var useInicio = false
    @State private var useFin = false
    @State private var localInicio: Date = Date()
    @State private var localFin: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Rango de fechas") {
                    Toggle("Desde", isOn: $useInicio)
                    if useInicio {
                        DatePicker("Fecha inicio", selection: $localInicio, displayedComponents: .date)
                    }
                    Toggle("Hasta", isOn: $useFin)
                    if useFin {
                        DatePicker("Fecha fin", selection: $localFin, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Limpiar filtros") {
                        useInicio = false
                        useFin = false
                        localInicio = Date()
                        localFin = Date()
                    }
                }
            }
            .navigationTitle("Filtros")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
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
                useInicio = fechaInicio != nil; useFin = fechaFin != nil
                if let f = fechaInicio { localInicio = f }
                if let f = fechaFin { localFin = f }
            }
        }
    }
}

// MARK: - Factura Detail View

struct FacturaDetailView: View {
    let facturaId: Int64
    @State private var factura: FacturaDto
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pdfToShare: PDFShareItem?
    @State private var descargandoPdf = false
    @State private var descargandoFePdf = false
    init(factura: FacturaDto) {
        self.facturaId = factura.id ?? 0
        self._factura = State(initialValue: factura)
    }

    var body: some View {
        ZStack {
            Theme.surface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // 1 · Cliente header
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel(text: "Cliente")
                        Text(factura.clienteDisplayName)
                            .font(.title.weight(.bold))
                            .tracking(-0.5)
                            .foregroundStyle(Theme.navyText)
                            .lineLimit(2)
                        HStack(spacing: 10) {
                            if let f = factura.fecha?.apiDate {
                                Text(f.displayString)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            if let s = factura.serie, !s.isEmpty {
                                Text("· \(s)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        if let ndf = factura.numeroDocumentoFiscal, !ndf.isEmpty {
                            Text(ndf)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                    // 2 · Status badges
                    HStack(spacing: 6) { pagoBadge; feBadge }
                        .padding(.horizontal, 4)

                    // 3 · Productos
                    if isLoading {
                        BrandCard {
                            HStack { Spacer(); ProgressView(); Spacer() }
                                .padding(.vertical, 20)
                        }
                    } else if let detalles = factura.detalles, !detalles.isEmpty {
                        BrandCard(padding: 14, radius: 18) {
                            VStack(spacing: 0) {
                                SectionLabel(text: "Productos · \(detalles.count)")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, 10)
                                ForEach(Array(detalles.enumerated()), id: \.offset) { idx, d in
                                    productoRow(d)
                                    if idx < detalles.count - 1 {
                                        Divider().background(Theme.divider)
                                    }
                                }
                            }
                        }
                    }

                    // 4 · Datos de pago
                    if factura.pagado == true {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 8) {
                                SectionLabel(text: "Pago")
                                if let mp = factura.montoPagado {
                                    LabeledContent("Monto", value: mp.currencyString)
                                }
                                if let fp = factura.fechaPago?.apiDate {
                                    LabeledContent("Fecha", value: fp.displayString)
                                }
                                if let fp = factura.formaPago {
                                    LabeledContent("Forma", value: MetodoPago(rawValue: fp)?.label ?? fp)
                                }
                            }
                        }
                    }

                    if let obs = factura.observaciones, !obs.isEmpty {
                        BrandCard {
                            VStack(alignment: .leading, spacing: 6) {
                                SectionLabel(text: "Observaciones")
                                Text(obs)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.navyText)
                            }
                        }
                    }

                    // 5 · Totales — card navy
                    TotalSummaryCard(rows: totalsRows, total: factura.total?.currencyString ?? "—")

                    Spacer().frame(height: 16)
                }
                .padding(.horizontal, 16)
            }
        }
        .navigationTitle(factura.serie.flatMap { $0.isEmpty ? nil : $0 } ?? "Factura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if factura.estadoFe == "EMITIDA" {
                    Button { Task { await descargarFePdf() } } label: {
                        if descargandoFePdf { ProgressView() }
                        else { Label("PDF FE", systemImage: "checkmark.seal") }
                    }
                }
                Button { Task { await descargarPdf() } } label: {
                    if descargandoPdf { ProgressView() }
                    else { Label("PDF", systemImage: "square.and.arrow.down") }
                }
            }
        }
        .sheet(item: $pdfToShare) { item in
            PDFShareSheet(data: item.data, suggestedName: item.suggestedName ?? "Factura.pdf")
        }
        .alert("Error",
               isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
        .task {
            guard factura.detalles == nil || factura.detalles!.isEmpty else { return }
            isLoading = true
            defer { isLoading = false }
            do { factura = try await APIClient.shared.getFactura(id: facturaId) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    @ViewBuilder
    private func productoRow(_ d: FacturaDetalleDto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(d.productoNombre ?? "Producto")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.navyText)
                HStack(spacing: 4) {
                    let cant = d.cantidad ?? 1
                    let precio = d.precioVenta ?? 0
                    let cantStr = cant == cant.rounded() ? String(Int(cant)) : String(format: "%.2f", cant)
                    Text("\(cantStr) × \(precio.currencyString)")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                    if let tasa = d.tasaItbms, tasa != "00" {
                        Text("· ITBMS \(TasaITBMS(rawValue: tasa)?.label ?? tasa)")
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            Spacer()
            Text(d.total?.currencyString ?? "—")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.navyText)
        }
        .padding(.vertical, 8)
    }

    private var totalsRows: [TotalSummaryCard.Row] {
        var rows: [TotalSummaryCard.Row] = []
        rows.append(.init(label: "Subtotal", value: factura.subtotal?.currencyString ?? "—"))
        if let d = factura.descuento, d > 0 {
            rows.append(.init(label: "Descuento", value: "−\(d.currencyString)", color: Theme.danger.opacity(0.9)))
        }
        rows.append(.init(label: "ITBMS", value: factura.impuestos?.currencyString ?? "—"))
        if let r = factura.retencionItbms, r > 0 {
            rows.append(.init(label: "Retención ITBMS", value: "−\(r.currencyString)", color: Theme.warning))
        }
        return rows
    }

    @ViewBuilder private var pagoBadge: some View {
        if factura.anulada == true {
            StatusBadge(text: "ANULADA", color: Theme.danger)
        } else {
            StatusBadge(text: factura.pagado == true ? "PAGADA" : "PENDIENTE",
                        color: factura.pagado == true ? Theme.success : Theme.amberDark)
        }
    }

    @ViewBuilder private var feBadge: some View {
        switch factura.estadoFe {
        case "EMITIDA": StatusBadge(text: "FE EMITIDA", color: Theme.info)
        case "ERROR":   StatusBadge(text: "FE ERROR",   color: Theme.danger)
        default:        EmptyView()
        }
    }

    private func descargarPdf() async {
        descargandoPdf = true
        defer { descargandoPdf = false }
        do {
            let data = try await APIClient.shared.downloadFacturaPdf(id: facturaId)
            pdfToShare = PDFShareItem(
                data: data,
                id: facturaId,
                suggestedName: "Factura_\(factura.clienteDisplayName.replacingOccurrences(of: " ", with: "_")).pdf"
            )
        } catch { errorMessage = error.localizedDescription }
    }

    private func descargarFePdf() async {
        descargandoFePdf = true
        defer { descargandoFePdf = false }
        do {
            let data = try await APIClient.shared.downloadFacturaFePdf(id: facturaId)
            pdfToShare = PDFShareItem(
                data: data,
                id: facturaId,
                suggestedName: "FacturaFE_\(factura.serie ?? String(facturaId)).pdf"
            )
        } catch { errorMessage = error.localizedDescription }
    }
}
