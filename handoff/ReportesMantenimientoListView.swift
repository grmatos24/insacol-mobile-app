// ReportesMantenimientoListView.swift
// Solo las partes a reemplazar — el ViewModel queda IGUAL.
// Reemplazar el body de `ReportesMantenimientoListView` y la struct `ReporteRow`.

import SwiftUI

// MARK: - View

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

    // MARK: REEMPLAZAR body

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Filter picker — MANTENER. Mes actual / Programados / Todos.
                    Picker("Filtro", selection: Binding(
                        get: { vm.filter },
                        set: { vm.filter = $0; Task { await vm.load() } }
                    )) {
                        Text("Mes actual").tag(APIClient.ReporteFilter.mesActual)
                        Text("Programados").tag(APIClient.ReporteFilter.proximoMes)
                        Text("Todos").tag(APIClient.ReporteFilter.todos)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    // Stat strip
                    StatStrip(items: stats)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    contentView
                }
            }
            .navigationTitle("Mantenimiento")
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .onChange(of: vm.search) { _, _ in Task { await vm.load() } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Theme.navy)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Nuevo reporte")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task { await vm.load() }
            // Sheets / alerts (sin cambios respecto al original)
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
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName ?? "Reporte.pdf")
            }
            .sheet(item: $preFacturaItem) { item in
                FacturaFormView(prefilledDto: item.dto, reporteMantenimientoId: item.reporteId) { saved in
                    preFacturaItem = nil
                    if saved { Task { await vm.load() } }
                }
            }
            .alert("¿Eliminar reporte?",
                   isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
                   presenting: toDelete) { r in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = r; toDelete = nil
                    Task { await vm.delete(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert("Error",
                   isPresented: Binding(get: { vm.errorMessage != nil }, set: { if !$0 { vm.errorMessage = nil } })) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }

    // MARK: - Stats derivados de vm.reportes

    private var stats: [StatStrip.Item] {
        let total = vm.reportes.count
        let borradores = vm.reportes.filter { $0.estado != .facturado }.count
        let vencidos = vm.reportes.filter {
            guard let d = $0.fechaProximoServicio?.apiDate else { return false }
            return d < Date()
        }.count
        return [
            .init(value: "\(total)", label: "Completados"),
            .init(value: "\(borradores)", label: "Borradores", color: Theme.amberDark),
            .init(value: "\(vencidos)", label: "Vencidos", color: Theme.danger),
        ]
    }

    // MARK: - Content

    @ViewBuilder
    private var contentView: some View {
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
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(vm.reportes) { r in
                            ReporteCardRow(
                                reporte: r,
                                clienteName: vm.displayName(for: r),
                                isGeneratingFactura: generandoFacturaId == r.id,
                                isDownloadingPdf: descargandoPdfId == r.id,
                                onTap: { editing = r },
                                onFacturar: { Task { await generarPreFactura(r) } },
                                onPdf: { Task { await descargarPdf(r) } }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .refreshable { await vm.load() }
            }
        }
    }

    // (mantener iguales: descargarPdf, generarPreFactura, iniciarMantenimiento, isFromPreviousYear)
}

// MARK: - ReporteCardRow (NUEVA — reemplaza ReporteRow)

private struct ReporteCardRow: View {
    let reporte: ReporteMantenimientoDto
    let clienteName: String
    let isGeneratingFactura: Bool
    let isDownloadingPdf: Bool
    let onTap: () -> Void
    let onFacturar: () -> Void
    let onPdf: () -> Void

    var body: some View {
        BrandCard(padding: 14, radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                // Header
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(clienteName)
                            .font(.headline)
                            .foregroundStyle(Theme.navyText)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let f = reporte.fechaServicio?.apiDate {
                                Text(f.displayString)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                            if let f = reporte.fechaProximoServicio?.apiDate {
                                Text("· próx \(f.displayString)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                    Spacer()
                    estadoBadge
                }

                // Divider punteado
                line

                // Footer — extintores + acciones inline
                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.amberDark)
                        Text("\(reporte.detalles?.count ?? 0) extintor\((reporte.detalles?.count ?? 0) == 1 ? "" : "es")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.navyText)
                    }
                    Spacer()
                    InlineActionPill(title: "PDF",
                                     systemImage: isDownloadingPdf ? nil : "square.and.arrow.down",
                                     action: onPdf)
                    if reporte.estado != .facturado {
                        InlineActionPill(title: isGeneratingFactura ? "..." : "Facturar",
                                         systemImage: "doc.text.fill",
                                         fg: .white,
                                         bg: Theme.success,
                                         action: onFacturar)
                    }
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        // Mantener swipe actions originales para eliminar / iniciar mantenimiento / ver
    }

    private var line: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .overlay(
                GeometryReader { g in
                    Path { p in
                        p.move(to: .zero); p.addLine(to: CGPoint(x: g.size.width, y: 0))
                    }
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundColor(Theme.divider)
                }
            )
    }

    @ViewBuilder
    private var estadoBadge: some View {
        let isFacturado = reporte.estado == .facturado
        StatusBadge(
            text: isFacturado ? "FACTURADO" : "BORRADOR",
            color: isFacturado ? Theme.success : Theme.amberDark
        )
    }
}

// FiltersSheet, descargarPdf, generarPreFactura, iniciarMantenimiento, isFromPreviousYear: MANTENER IGUAL al archivo original.
