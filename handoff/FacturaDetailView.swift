// FacturaDetailView — reemplaza la struct FacturaDetailView dentro de FacturasListView.swift
// FacturasListView, FacturasListViewModel, FacturaRow y FacturasFiltersSheet quedan IGUAL.

import SwiftUI

struct FacturaDetailView: View {
    let facturaId: Int64
    @State private var factura: FacturaDto
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pdfToShare: PDFShareItem?
    @State private var descargandoPdf = false
    @State private var descargandoFePdf = false
    @State private var showingPagoSheet = false  // TODO: implementar sheet de pago

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

                    // 2 · Status row
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

                    // 4 · Datos de pago (cuando corresponde)
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
                                    LabeledContent("Forma",
                                                   value: MetodoPago(rawValue: fp)?.label ?? fp)
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

                    // 5 · Totales — navy card
                    TotalSummaryCard(
                        rows: totalsRows,
                        total: factura.total?.currencyString ?? "—"
                    )

                    // 6 · CTA registrar pago
                    if factura.pagado != true && factura.anulada != true {
                        BigCTAButton(title: "Registrar pago",
                                     systemImage: "creditcard.fill") {
                            // TODO: presentar sheet de registro de pago
                            showingPagoSheet = true
                        }
                        .padding(.top, 4)
                    }

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

    // MARK: - Subviews

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
            rows.append(.init(label: "Descuento",
                              value: "−\(d.currencyString)",
                              color: Theme.danger.opacity(0.9)))
        }
        rows.append(.init(label: "ITBMS", value: factura.impuestos?.currencyString ?? "—"))
        if let r = factura.retencionItbms, r > 0 {
            rows.append(.init(label: "Retención ITBMS",
                              value: "−\(r.currencyString)",
                              color: Theme.warning))
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

    // MARK: - Actions (sin cambios respecto al original)

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
