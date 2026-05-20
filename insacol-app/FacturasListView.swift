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
    @State private var toAnular: FacturaDto?
    @State private var toEmitirFe: FacturaDto?
    @State private var descargandoPdfId: Int64?
    @State private var descargandoXmlId: Int64?
    @State private var pdfToShare: PDFShareItem?
    @State private var xmlToShare: XMLShareItem?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
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
            .navigationTitle("Facturas")
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
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task { await vm.load() }
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
            .sheet(item: $xmlToShare) { item in
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName)
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
            .alert("¿Emitir factura electrónica?",
                   isPresented: Binding(
                    get: { toEmitirFe != nil },
                    set: { if !$0 { toEmitirFe = nil } }
                   ),
                   presenting: toEmitirFe) { f in
                Button("Cancelar", role: .cancel) { toEmitirFe = nil }
                Button("Emitir") {
                    let target = f; toEmitirFe = nil
                    Task { await vm.emitirFe(target) }
                }
            } message: { _ in
                Text("Se enviará la factura a la DGI vía HKA. Asegúrate de que los datos estén correctos.")
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
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
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

                                if f.pagado != true && f.anulada != true {
                                    Button(role: .destructive) {
                                        toAnular = f
                                    } label: {
                                        Label("Anular", systemImage: "xmark.circle")
                                    }
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if f.estadoFe == "EMITIDA" {
                                    Button {
                                        Task { await descargarXml(f) }
                                    } label: {
                                        if descargandoXmlId == f.id {
                                            ProgressView()
                                        } else {
                                            Label("XML", systemImage: "doc.badge.arrow.up")
                                        }
                                    }
                                    .tint(.teal)
                                } else if f.anulada != true {
                                    Button {
                                        toEmitirFe = f
                                    } label: {
                                        Label("Emitir FE", systemImage: "bolt.fill")
                                    }
                                    .tint(.orange)
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .refreshable { await vm.load() }
            }
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

    private func descargarXml(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        descargandoXmlId = id
        defer { descargandoXmlId = nil }
        do {
            let data = try await APIClient.shared.downloadFacturaXml(id: id)
            xmlToShare = XMLShareItem(
                data: data,
                suggestedName: "Factura_\(f.serie ?? String(id)).xml"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - XML Share Item

struct XMLShareItem: Identifiable {
    let data: Data
    let suggestedName: String
    var id: String { suggestedName }
}

// MARK: - Factura Row

private struct FacturaRow: View {
    let factura: FacturaDto

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(factura.clienteDisplayName).font(.headline).lineLimit(1)
                Spacer()
                pagoBadge
            }
            HStack(spacing: 8) {
                if let s = factura.serie, !s.isEmpty {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
                if let f = factura.fecha?.apiDate {
                    Label(f.displayString, systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                feBadge
            }
            if let total = factura.total {
                Text(total.currencyString).font(.subheadline.bold())
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var pagoBadge: some View {
        if factura.anulada == true {
            Text("ANULADA")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        } else {
            let pagada = factura.pagado == true
            let color: Color = pagada ? .green : .orange
            Text(pagada ? "PAGADA" : "PENDIENTE")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var feBadge: some View {
        let estado = factura.estadoFe ?? "BORRADOR"
        let (label, color): (String, Color) = switch estado {
        case "EMITIDA": ("FE EMITIDA", .teal)
        case "ERROR": ("FE ERROR", .red)
        case "ANULADA": ("FE ANULADA", .gray)
        default: ("BORRADOR", .secondary)
        }
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
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
                        useInicio = false; useFin = false
                        fechaInicio = nil; fechaFin = nil
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
