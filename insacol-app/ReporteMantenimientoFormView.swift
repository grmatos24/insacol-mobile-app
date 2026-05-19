import SwiftUI

// MARK: - View model

@MainActor
@Observable
final class ReporteMantenimientoFormViewModel: Identifiable {
    let existingId: Int64?
    let isReadOnly: Bool

    // Header
    var clienteId: Int64?
    var clienteNombre: String = ""
    var fechaServicio: Date = Date()
    var fechaProximoServicio: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var observacionesGenerales: String = ""

    // Detalles (uso un wrapper Identifiable estable porque el detalle puede no tener id aún)
    var detalles: [DetalleItem] = []

    // UI state
    var showingClientePicker = false
    var showingExtintorPicker = false
    var isSubmitting = false
    var errorMessage: String?
    var savedSuccessfully = false
    var pdfDataToShare: Data?

    struct DetalleItem: Identifiable, Hashable {
        let localId: UUID
        var data: ReporteMantenimientoDetalleDto
        var displayName: String     // nombre del extintor para mostrar
        var isExpanded: Bool = false

        init(localId: UUID = UUID(),
             data: ReporteMantenimientoDetalleDto,
             displayName: String,
             isExpanded: Bool = false) {
            self.localId = localId
            self.data = data
            self.displayName = displayName
            self.isExpanded = isExpanded
        }

        var id: UUID { localId }
    }

    init(existing: ReporteMantenimientoDto?) {
        self.existingId = existing?.id
        self.isReadOnly = (existing?.estado == .facturado)

        if let r = existing {
            clienteId = r.clienteId
            clienteNombre = {
                if let s = r.clienteSubEmpresa, !s.isEmpty { return s }
                if let e = r.clienteEmpresa, !e.isEmpty { return e }
                return "Cliente #\(r.clienteId.map(String.init) ?? "-")"
            }()
            if let s = r.fechaServicio?.apiDate { fechaServicio = s }
            if let s = r.fechaProximoServicio?.apiDate { fechaProximoServicio = s }
            observacionesGenerales = r.observacionesGenerales ?? ""
            detalles = (r.detalles ?? []).map { d in
                DetalleItem(data: d, displayName: "Extintor")
            }
        }
    }

    // MARK: - Actions

    func setCliente(_ c: ClienteDto) {
        // Si cambias de cliente con detalles cargados, los limpiamos para evitar mezclar extintores.
        if clienteId != c.id, !detalles.isEmpty {
            detalles.removeAll()
        }
        clienteId = c.id
        clienteNombre = c.displayName
    }

    func addExtintor(_ e: ExtintorClienteDto) {
        let dto = ReporteMantenimientoDetalleDto(
            id: nil,
            extintorClienteId: e.id,
            extintorCatalogoId: e.extintorCatalogoId,
            numeroSerie: e.numeroSerie,
            ubicacionHabitual: e.ubicacionHabitual,
            codigoInsacol: e.codigoInsacol,
            fechaPh: e.fechaPh,
            fechaProxPh: e.fechaProxPh,
            recargado: false,
            cantidadAgenteUtilizado: 0,
            pruebaHidrostatica: false,
            cambioManguera: false,
            correa: false,
            manometro: false,
            gancho: false,
            pasador: false,
            descartado: false,
            observaciones: nil
        )
        detalles.append(
            DetalleItem(
                data: dto,
                displayName: e.extintorNombre ?? "Extintor",
                isExpanded: true
            )
        )
    }

    func removeDetalle(_ d: DetalleItem) {
        detalles.removeAll { $0.localId == d.localId }
    }

    /// Cuando se marca descartado: limpia trabajos, código = "descartado", agrega nota.
    func toggleDescartado(localId: UUID, descartado: Bool) {
        guard let i = detalles.firstIndex(where: { $0.localId == localId }) else { return }
        detalles[i].data.descartado = descartado
        if descartado {
            detalles[i].data.recargado = false
            detalles[i].data.cantidadAgenteUtilizado = 0
            detalles[i].data.pruebaHidrostatica = false
            detalles[i].data.cambioManguera = false
            detalles[i].data.correa = false
            detalles[i].data.manometro = false
            detalles[i].data.gancho = false
            detalles[i].data.pasador = false
            let originalCodigo = detalles[i].data.codigoInsacol ?? ""
            detalles[i].data.codigoInsacol = "descartado"
            let serie = detalles[i].data.numeroSerie ?? "?"
            let ubic = detalles[i].data.ubicacionHabitual ?? "—"
            let nombre = detalles[i].displayName
            let nota = "Extintor \(nombre) (cód \(originalCodigo)) serie \(serie) en \(ubic) queda descartado."
            if observacionesGenerales.contains(nota) == false {
                if !observacionesGenerales.isEmpty {
                    observacionesGenerales += "\n"
                }
                observacionesGenerales += nota
            }
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        guard clienteId != nil else { return false }
        guard !detalles.isEmpty else { return false }
        for d in detalles {
            let nSerie = (d.data.numeroSerie ?? "").trimmingCharacters(in: .whitespaces)
            let codigo = (d.data.codigoInsacol ?? "").trimmingCharacters(in: .whitespaces)
            if nSerie.isEmpty { return false }
            if codigo.isEmpty { return false }
        }
        return true
    }

    // MARK: - Submit

    func submit() async {
        guard isValid else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        let dto = ReporteMantenimientoDto(
            id: existingId,
            clienteId: clienteId,
            clienteEmpresa: nil,
            clienteSubEmpresa: nil,
            fechaServicio: fechaServicio.apiDateString,
            fechaProximoServicio: fechaProximoServicio.apiDateString,
            observacionesGenerales: observacionesGenerales.isEmpty ? nil : observacionesGenerales,
            estado: nil,
            facturaId: nil,
            detalles: detalles.map { $0.data }
        )

        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateReporte(id: id, dto: dto)
            } else {
                _ = try await APIClient.shared.saveReporte(dto)
            }
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func downloadPdf() async {
        guard let id = existingId else { return }
        do {
            let data = try await APIClient.shared.downloadReportePdf(id: id)
            self.pdfDataToShare = data
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - View

struct ReporteMantenimientoFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State var vm: ReporteMantenimientoFormViewModel
    let onClose: (Bool) -> Void

    init(reporte: ReporteMantenimientoDto?, onClose: @escaping (Bool) -> Void) {
        self._vm = State(initialValue: ReporteMantenimientoFormViewModel(existing: reporte))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Form {
                clienteSection
                fechasSection
                extintoresSection
                observacionesSection
                if vm.existingId != nil {
                    Section {
                        Button {
                            Task { await vm.downloadPdf() }
                        } label: {
                            Label("Descargar PDF", systemImage: "square.and.arrow.down")
                        }
                    }
                }
            }
            .disabled(vm.isReadOnly && vm.existingId != nil ? false : false) // permitir edición; solo bloquea al guardar si está facturado
            .navigationTitle(vm.existingId == nil ? "Nuevo reporte" : (vm.isReadOnly ? "Reporte (facturado)" : "Editar reporte"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") {
                        onClose(false)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !vm.isReadOnly {
                        Button {
                            Task { await vm.submit() }
                        } label: {
                            if vm.isSubmitting { ProgressView() }
                            else { Text("Guardar") }
                        }
                        .disabled(!vm.isValid || vm.isSubmitting)
                    }
                }
            }
            .sheet(isPresented: $vm.showingClientePicker) {
                ClienteSelectorView { c in vm.setCliente(c) }
            }
            .sheet(isPresented: $vm.showingExtintorPicker) {
                if let cid = vm.clienteId {
                    let excludeIds = Set(vm.detalles.compactMap { $0.data.extintorClienteId })
                    ExtintorClientePickerView(clienteId: cid, excludeIds: excludeIds) { e in
                        vm.addExtintor(e)
                    }
                } else {
                    Text("Selecciona un cliente primero")
                        .padding()
                }
            }
            .sheet(item: Binding(
                get: { vm.pdfDataToShare.map { PDFShareItem(data: $0, id: vm.existingId ?? 0) } },
                set: { if $0 == nil { vm.pdfDataToShare = nil } }
            )) { item in
                PDFShareSheet(data: item.data, suggestedName: "reporte-\(item.id).pdf")
            }
            .onChange(of: vm.savedSuccessfully) { _, newValue in
                if newValue {
                    onClose(true)
                    dismiss()
                }
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

    // MARK: Sections

    @ViewBuilder
    private var clienteSection: some View {
        Section("Cliente") {
            HStack {
                VStack(alignment: .leading) {
                    Text(vm.clienteId == nil ? "Sin cliente" : vm.clienteNombre)
                        .foregroundStyle(vm.clienteId == nil ? .secondary : .primary)
                }
                Spacer()
                if !vm.isReadOnly {
                    Button("Cambiar") { vm.showingClientePicker = true }
                }
            }
            if vm.clienteId == nil {
                Text("Selecciona un cliente para agregar extintores.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var fechasSection: some View {
        Section("Fechas") {
            DatePicker("Fecha de servicio",
                       selection: $vm.fechaServicio,
                       displayedComponents: .date)
                .disabled(vm.existingId != nil) // no editable en edición
            DatePicker("Próximo servicio",
                       selection: $vm.fechaProximoServicio,
                       displayedComponents: .date)
        }
    }

    @ViewBuilder
    private var extintoresSection: some View {
        Section {
            if vm.detalles.isEmpty {
                Text("Sin extintores agregados.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($vm.detalles, id: \.localId) { $item in
                    ExtintorCard(
                        item: $item,
                        readOnly: vm.isReadOnly,
                        onDelete: { vm.removeDetalle(item) },
                        onToggleDescartado: { v in
                            vm.toggleDescartado(localId: item.localId, descartado: v)
                        }
                    )
                }
            }
            if !vm.isReadOnly {
                Button {
                    if vm.clienteId == nil {
                        vm.errorMessage = "Selecciona un cliente primero."
                    } else {
                        vm.showingExtintorPicker = true
                    }
                } label: {
                    Label("Agregar extintor", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            HStack {
                Text("Extintores")
                Spacer()
                Text("\(vm.detalles.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var observacionesSection: some View {
        Section("Observaciones generales") {
            TextField("Notas...", text: $vm.observacionesGenerales, axis: .vertical)
                .lineLimit(3...8)
        }
    }
}

// MARK: - Extintor card (compact + expand)

private struct ExtintorCard: View {
    @Binding var item: ReporteMantenimientoFormViewModel.DetalleItem
    let readOnly: Bool
    let onDelete: () -> Void
    let onToggleDescartado: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName)
                        .font(.headline)
                        .strikethrough(item.data.descartado == true)
                    HStack(spacing: 8) {
                        if let s = item.data.numeroSerie, !s.isEmpty {
                            Label(s, systemImage: "barcode").font(.caption2)
                        }
                        if let c = item.data.codigoInsacol, !c.isEmpty {
                            Label(c, systemImage: "number").font(.caption2)
                        }
                    }
                    .foregroundStyle(.secondary)
                    if let u = item.data.ubicacionHabitual, !u.isEmpty {
                        Label(u, systemImage: "mappin")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    workChipsRow
                }
                Spacer()
                Button {
                    withAnimation { item.isExpanded.toggle() }
                } label: {
                    Image(systemName: item.isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .opacity(item.data.descartado == true ? 0.55 : 1.0)

            if item.isExpanded {
                expandedEditor
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var workChipsRow: some View {
        let chips: [(String, Bool)] = [
            ("P.H.", item.data.pruebaHidrostatica == true),
            ("Mang.", item.data.cambioManguera == true),
            ("Correa", item.data.correa == true),
            ("Manóm.", item.data.manometro == true),
            ("Gancho", item.data.gancho == true),
            ("Pasador", item.data.pasador == true),
            ("Recarg.", item.data.recargado == true)
        ]
        let active = chips.filter { $0.1 }
        if !active.isEmpty {
            HStack(spacing: 4) {
                ForEach(active.indices, id: \.self) { i in
                    Text(active[i].0)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(Color.blue)
                        .clipShape(Capsule())
                }
            }
            .padding(.top, 2)
        }
        if item.data.descartado == true {
            Text("DESCARTADO")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var expandedEditor: some View {
        Divider()
        Group {
            row("Serie") {
                TextField("Serie", text: Binding(
                    get: { item.data.numeroSerie ?? "" },
                    set: { item.data.numeroSerie = $0 }
                ))
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
            }
            row("Cód. Insacol") {
                TextField("Código", text: Binding(
                    get: { item.data.codigoInsacol ?? "" },
                    set: { item.data.codigoInsacol = $0 }
                ))
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
            }
            row("Ubicación") {
                TextField("Ubicación", text: Binding(
                    get: { item.data.ubicacionHabitual ?? "" },
                    set: { item.data.ubicacionHabitual = $0 }
                ))
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
            }
            row("Año P.H.") {
                TextField("yyyy", value: Binding(
                    get: { item.data.fechaPh },
                    set: { item.data.fechaPh = $0 }
                ), format: .number.grouping(.never))
                .appKeyboard(.numberPad)
                .multilineTextAlignment(.trailing)
            }
            row("Año próx. P.H.") {
                TextField("yyyy", value: Binding(
                    get: { item.data.fechaProxPh },
                    set: { item.data.fechaProxPh = $0 }
                ), format: .number.grouping(.never))
                .appKeyboard(.numberPad)
                .multilineTextAlignment(.trailing)
            }
        }
        .disabled(item.data.descartado == true || readOnly)

        Toggle("Prueba hidrostática", isOn: boolBinding(\.pruebaHidrostatica))
            .disabled(item.data.descartado == true || readOnly)
        Toggle("Cambio manguera", isOn: boolBinding(\.cambioManguera))
            .disabled(item.data.descartado == true || readOnly)
        Toggle("Correa", isOn: boolBinding(\.correa))
            .disabled(item.data.descartado == true || readOnly)
        Toggle("Manómetro", isOn: boolBinding(\.manometro))
            .disabled(item.data.descartado == true || readOnly)
        Toggle("Gancho", isOn: boolBinding(\.gancho))
            .disabled(item.data.descartado == true || readOnly)
        Toggle("Pasador", isOn: boolBinding(\.pasador))
            .disabled(item.data.descartado == true || readOnly)
        Toggle("Recargado", isOn: boolBinding(\.recargado))
            .disabled(item.data.descartado == true || readOnly)
        if item.data.recargado == true {
            row("Cantidad (lbs)") {
                TextField("0", value: Binding(
                    get: { item.data.cantidadAgenteUtilizado ?? 0 },
                    set: { item.data.cantidadAgenteUtilizado = $0 }
                ), format: .number)
                .appKeyboard(.decimal)
                .multilineTextAlignment(.trailing)
            }
        }

        Toggle("Descartado", isOn: Binding(
            get: { item.data.descartado ?? false },
            set: { onToggleDescartado($0) }
        ))
        .tint(.red)
        .disabled(readOnly)

        row("Observaciones") {
            TextField("Notas...", text: Binding(
                get: { item.data.observaciones ?? "" },
                set: { item.data.observaciones = $0 }
            ), axis: .vertical)
            .lineLimit(1...3)
        }
        .disabled(readOnly)

        if !readOnly {
            HStack {
                Spacer()
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Quitar del reporte", systemImage: "trash")
                }
            }
            .padding(.top, 4)
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<ReporteMantenimientoDetalleDto, Bool?>) -> Binding<Bool> {
        Binding(
            get: { item.data[keyPath: keyPath] ?? false },
            set: { item.data[keyPath: keyPath] = $0 }
        )
    }

    @ViewBuilder
    private func row<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            content()
        }
    }
}

// MARK: - PDF Share

struct PDFShareItem: Identifiable {
    let data: Data
    let id: Int64
}

#if os(iOS)
import UIKit

struct PDFShareSheet: UIViewControllerRepresentable {
    let data: Data
    let suggestedName: String

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Guardar a un archivo temporal para preservar el nombre
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedName)
        try? data.write(to: url)
        return UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#else
struct PDFShareSheet: View {
    let data: Data
    let suggestedName: String
    var body: some View {
        Text("Compartir PDF disponible solo en iOS.")
    }
}
#endif

#Preview {
    ReporteMantenimientoFormView(reporte: nil) { _ in }
}
