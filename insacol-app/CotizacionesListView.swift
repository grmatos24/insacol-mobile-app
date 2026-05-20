import SwiftUI

@MainActor
@Observable
final class CotizacionesListViewModel {
    var cotizaciones: [CotizacionDto] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?
    var search: String = ""

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listCotizaciones(searchTerm: search, size: 50)
            self.cotizaciones = page.content
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ c: CotizacionDto) async {
        guard let id = c.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await APIClient.shared.deleteCotizacion(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func facturar(_ c: CotizacionDto) async {
        guard let id = c.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await APIClient.shared.createFacturaFromCotizacion(cotizacionId: id)
            successMessage = "Factura creada exitosamente. Puedes verla en la pestaña Facturas."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CotizacionesListView: View {
    @State private var vm = CotizacionesListViewModel()
    @State private var searchTask: Task<Void, Never>?
    @State private var showingAdd = false
    @State private var editing: CotizacionDto?
    @State private var toDelete: CotizacionDto?
    @State private var toFacturar: CotizacionDto?
    @State private var descargandoPdfId: Int64?
    @State private var pdfToShare: PDFShareItem?

    private var successMessageBinding: Binding<Bool> {
        Binding(
            get: { vm.successMessage != nil },
            set: { if !$0 { vm.successMessage = nil } }
        )
    }

    private var errorMessageBinding: Binding<Bool> {
        Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )
    }

    private func descargarPdf(_ c: CotizacionDto) async {
        guard let id = c.id else { return }
        descargandoPdfId = id
        defer { descargandoPdfId = nil }
        do {
            let data = try await APIClient.shared.downloadCotizacionPdf(id: id)
            pdfToShare = PDFShareItem(
                data: data,
                id: id,
                suggestedName: "Cotizacion_\(c.clienteDisplayName.replacingOccurrences(of: " ", with: "_")).pdf"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading && vm.cotizaciones.isEmpty {
            ProgressView("Cargando...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.cotizaciones.isEmpty {
            ContentUnavailableView(
                "Sin cotizaciones",
                systemImage: "doc.text",
                description: Text("Toca + para crear la primera cotización.")
            )
        } else {
            List {
                ForEach(vm.cotizaciones) { c in
                    CotizacionListRow(
                        cotizacion: c,
                        descargandoPdfId: descargandoPdfId,
                        onTap: { if c.facturada != true { editing = c } },
                        onEditar: { editing = c },
                        onFacturar: { toFacturar = c },
                        onEliminar: { toDelete = c },
                        onPdf: { Task { await descargarPdf(c) } }
                    )
                }
            }
            .listStyle(.plain)
            .refreshable { await vm.load() }
        }
    }

    var body: some View {
        NavigationStack {
            contentView
            .navigationTitle("Cotizaciones")
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
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                CotizacionFormView(cotizacion: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { c in
                CotizacionFormView(cotizacion: c) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $pdfToShare) { item in
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName ?? "Cotizacion.pdf")
            }
            .alert("¿Convertir en factura?",
                   isPresented: Binding(
                    get: { toFacturar != nil },
                    set: { if !$0 { toFacturar = nil } }
                   ),
                   presenting: toFacturar) { c in
                Button("Cancelar", role: .cancel) { toFacturar = nil }
                Button("Facturar") {
                    let target = c
                    toFacturar = nil
                    Task { await vm.facturar(target) }
                }
            } message: { c in
                Text("Se creará una factura para \(c.clienteDisplayName). Esta acción no se puede deshacer.")
            }
            .alert("¿Eliminar cotización?",
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
            .alert("Factura creada",
                   isPresented: successMessageBinding,
                   presenting: vm.successMessage) { _ in
                Button("OK") { vm.successMessage = nil }
            } message: { msg in Text(msg) }
            .alert("Error",
                   isPresented: errorMessageBinding) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }
}

private struct CotizacionListRow: View {
    let cotizacion: CotizacionDto
    let descargandoPdfId: Int64?
    let onTap: () -> Void
    let onEditar: () -> Void
    let onFacturar: () -> Void
    let onEliminar: () -> Void
    let onPdf: () -> Void

    var body: some View {
        CotizacionRow(cotizacion: cotizacion)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if cotizacion.facturada != true {
                    Button(role: .destructive, action: onEliminar) {
                        Label("Eliminar", systemImage: "trash")
                    }
                }
                Button(action: onPdf) {
                    if descargandoPdfId == cotizacion.id {
                        ProgressView()
                    } else {
                        Label("PDF", systemImage: "square.and.arrow.down")
                    }
                }
                .tint(.indigo)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if cotizacion.facturada != true {
                    Button(action: onEditar) {
                        Label("Editar", systemImage: "pencil")
                    }
                    .tint(.blue)
                    Button(action: onFacturar) {
                        Label("Facturar", systemImage: "doc.text.fill")
                    }
                    .tint(.green)
                }
            }
    }
}

private struct CotizacionRow: View {
    let cotizacion: CotizacionDto

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(cotizacion.clienteDisplayName).font(.headline).lineLimit(1)
                    Spacer()
                    if let facturada = cotizacion.facturada {
                        let color: Color = facturada ? .green : .orange
                        Text(facturada ? "FACTURADA" : "PENDIENTE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color.opacity(0.15))
                            .foregroundStyle(color)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 12) {
                    if let s = cotizacion.serie, !s.isEmpty {
                        Text(s).font(.caption).foregroundStyle(.secondary)
                    }
                    if let f = cotizacion.fecha?.apiDate {
                        Label(f.displayString, systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let total = cotizacion.total {
                    Text(total.currencyString).font(.subheadline.bold())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
