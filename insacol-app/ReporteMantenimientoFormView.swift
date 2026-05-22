import SwiftUI

// MARK: - View model

@MainActor
@Observable
final class ReporteMantenimientoFormViewModel: Identifiable {
    let existingId: Int64?
    let isReadOnly: Bool
    let isCloneFromPrevious: Bool

    // Header
    var clienteId: Int64?
    var clienteNombre: String = ""
    var fechaServicio: Date = Date()
    var fechaProximoServicio: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var observacionesGenerales: String = ""

    // Detalles (uso un wrapper Identifiable estable porque el detalle puede no tener id aún)
    var detalles: [DetalleItem] = []

    // Filtros sobre la lista de extintores
    var filterMarcaId: Int64?
    var filterTipoId: Int64?
    var filterCapacidadId: Int64?

    // UI state
    var showingClientePicker = false
    var showingExtintorPicker = false
    var changingCatalogForLocalId: UUID?
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

    init(existing: ReporteMantenimientoDto?, cloneFrom: ReporteMantenimientoDto? = nil) {
        // Modo clone: actúa como nuevo (existingId = nil) pero pre-llena desde cloneFrom.
        let source = existing ?? cloneFrom
        self.existingId = existing?.id
        self.isCloneFromPrevious = (existing == nil && cloneFrom != nil)
        self.isReadOnly = (existing?.estado == .facturado)

        if let r = source {
            clienteId = r.clienteId
            clienteNombre = {
                if let s = r.clienteSubEmpresa, !s.isEmpty { return s }
                if let e = r.clienteEmpresa, !e.isEmpty { return e }
                return "Cargando cliente..."
            }()
            if existing != nil {
                if let s = r.fechaServicio?.apiDate { fechaServicio = s }
                if let s = r.fechaProximoServicio?.apiDate { fechaProximoServicio = s }
            }
            // Si es clone: hoy + 1 año (por defecto que ya tenemos)
            observacionesGenerales = existing != nil ? (r.observacionesGenerales ?? "") : ""
            detalles = (r.detalles ?? []).map { d in
                var data = d
                if existing == nil {
                    // Clone "limpio": conservamos identidad y datos físicos del extintor,
                    // pero reseteamos los trabajos realizados, observaciones y descartado.
                    data.id = nil
                    data.recargado = false
                    data.cantidadAgenteUtilizado = 0
                    data.pruebaHidrostatica = false
                    data.cambioManguera = false
                    data.correa = false
                    data.manometro = false
                    data.gancho = false
                    data.pasador = false
                    data.descartado = false
                    data.observaciones = nil
                }
                return DetalleItem(data: data, displayName: "Extintor")
            }
            sortDetallesByCodigo()
        }
    }

    /// Resuelve "Marca Tipo Capacidad" para cada detalle desde el catálogo.
    func resolveDetalleNames() async {
        await CatalogCache.shared.loadIfNeeded()
        let cache = CatalogCache.shared
        for i in detalles.indices {
            let id = detalles[i].data.extintorCatalogoId
            detalles[i].displayName = cache.displayName(for: id)
        }
    }

    /// Cambia el catálogo (marca/tipo/capacidad) de un detalle ya agregado.
    func changeCatalogo(localId: UUID, extintor: ExtintorDto, displayName: String) {
        guard let i = detalles.firstIndex(where: { $0.localId == localId }) else { return }
        detalles[i].data.extintorCatalogoId = extintor.id
        detalles[i].displayName = displayName
        // Aseguramos que la card siga expandida tras el cambio.
        detalles[i].isExpanded = true
        // Limpiamos cualquier filtro activo para garantizar que el usuario
        // pueda ver el extintor que acaba de modificar.
        clearFilters()
    }

    /// Cuando se edita un reporte, el backend solo da clienteId. Resolvemos el nombre.
    func resolveClienteName() async {
        guard let id = clienteId else { return }
        // Si ya tenemos un nombre "real" (no "Cargando..."), no hacemos nada.
        if !clienteNombre.isEmpty && clienteNombre != "Cargando cliente..." { return }
        do {
            let page = try await APIClient.shared.listClientes(size: 500)
            if let c = page.content.first(where: { $0.id == id }) {
                clienteNombre = c.displayName
            }
        } catch {
            // Si falla, dejamos el placeholder; no es crítico
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
        // Preferimos "Marca Tipo Capacidad" del catálogo; si no, usamos el nombre denormalizado del ExtintorCliente.
        let displayName = CatalogCache.shared.displayName(for: e.extintorCatalogoId)
        let finalName = displayName != "Extintor" ? displayName : (e.extintorNombre ?? "Extintor")
        detalles.append(
            DetalleItem(
                data: dto,
                displayName: finalName,
                isExpanded: true
            )
        )
        sortDetallesByCodigo()
    }

    func addBlankDetalle() {
        let dto = ReporteMantenimientoDetalleDto(
            id: nil,
            extintorClienteId: nil,
            extintorCatalogoId: nil,
            numeroSerie: nil,
            ubicacionHabitual: nil,
            codigoInsacol: nil,
            fechaPh: nil,
            fechaProxPh: nil,
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
        detalles.append(DetalleItem(data: dto, displayName: "Nuevo extintor", isExpanded: true))
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

    /// Ordena los detalles por `codigoInsacol` (ascendente, locale-aware).
    /// Los descartados (código "descartado") quedan al final.
    func sortDetallesByCodigo() {
        detalles.sort { a, b in
            let ca = (a.data.codigoInsacol ?? "").trimmingCharacters(in: .whitespaces)
            let cb = (b.data.codigoInsacol ?? "").trimmingCharacters(in: .whitespaces)
            let aDescartado = ca.lowercased() == "descartado"
            let bDescartado = cb.lowercased() == "descartado"
            if aDescartado != bDescartado { return !aDescartado }
            return ca.localizedStandardCompare(cb) == .orderedAscending
        }
    }

    // MARK: - Filtros sobre la lista de extintores

    var hasActiveFilter: Bool {
        filterMarcaId != nil || filterTipoId != nil || filterCapacidadId != nil
    }

    func clearFilters() {
        filterMarcaId = nil
        filterTipoId = nil
        filterCapacidadId = nil
    }

    /// Devuelve true si el detalle pasa los filtros activos.
    func matchesFilter(_ item: DetalleItem) -> Bool {
        guard hasActiveFilter else { return true }
        guard let catId = item.data.extintorCatalogoId,
              let ext = CatalogCache.shared.extintores.first(where: { $0.id == catId })
        else {
            // Si no encontramos el catálogo pero hay filtros activos, excluir.
            return false
        }
        if let m = filterMarcaId, ext.marcaId != m { return false }
        if let t = filterTipoId, ext.tipoId != t { return false }
        if let c = filterCapacidadId, ext.capacidadId != c { return false }
        return true
    }

    /// Opciones de filtro derivadas de los extintores presentes en el reporte (id → nombre).
    var availableMarcas: [(Int64, String)] {
        let cache = CatalogCache.shared
        let ids = Set(detalles.compactMap { d -> Int64? in
            cache.extintores.first { $0.id == d.data.extintorCatalogoId }?.marcaId
        })
        return ids.compactMap { id in
            cache.marcas[id].map { (id, $0) }
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var availableTipos: [(Int64, String)] {
        let cache = CatalogCache.shared
        let ids = Set(detalles.compactMap { d -> Int64? in
            cache.extintores.first { $0.id == d.data.extintorCatalogoId }?.tipoId
        })
        return ids.compactMap { id in
            cache.tipos[id].map { (id, $0) }
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var availableCapacidades: [(Int64, String)] {
        let cache = CatalogCache.shared
        let ids = Set(detalles.compactMap { d -> Int64? in
            cache.extintores.first { $0.id == d.data.extintorCatalogoId }?.capacidadId
        })
        return ids.compactMap { id in
            cache.capacidades[id].map { (id, $0) }
        }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }

    var filteredCount: Int {
        detalles.filter(matchesFilter).count
    }

    // MARK: - Validation

    var isValid: Bool {
        guard clienteId != nil else { return false }
        guard !detalles.isEmpty else { return false }
        for d in detalles {
            if d.data.extintorCatalogoId == nil { return false }
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

    init(reporte: ReporteMantenimientoDto?,
         cloneFrom: ReporteMantenimientoDto? = nil,
         onClose: @escaping (Bool) -> Void) {
        self._vm = State(initialValue: ReporteMantenimientoFormViewModel(existing: reporte, cloneFrom: cloneFrom))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Form {
                clienteSection
                fechasSection
                filtrosSection
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
            .navigationTitle(
                vm.existingId == nil
                    ? (vm.isCloneFromPrevious ? "Iniciar mantenimiento" : "Nuevo reporte")
                    : (vm.isReadOnly ? "Reporte (facturado)" : "Editar reporte")
            )
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
            .task {
                await vm.resolveClienteName()
                await vm.resolveDetalleNames()
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
                get: { vm.changingCatalogForLocalId.map { ChangingCatalogContext(localId: $0) } },
                set: { if $0 == nil { vm.changingCatalogForLocalId = nil } }
            )) { ctx in
                ExtintorCatalogoPickerView { ext, name in
                    vm.changeCatalogo(localId: ctx.localId, extintor: ext, displayName: name)
                }
            }
            .sheet(item: Binding(
                get: {
                    vm.pdfDataToShare.map {
                        PDFShareItem(
                            data: $0,
                            id: vm.existingId ?? 0,
                            suggestedName: reportePdfFilename(clienteName: vm.clienteNombre)
                        )
                    }
                },
                set: { if $0 == nil { vm.pdfDataToShare = nil } }
            )) { item in
                PDFShareSheet(
                    data: item.data,
                    suggestedName: item.suggestedName ?? "Reporte.pdf"
                )
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
    private var filtrosSection: some View {
        if vm.detalles.count >= 2 {
            Section {
                filtrosRow
            } header: {
                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filtrar extintores")
                }
            } footer: {
                if vm.hasActiveFilter && vm.filteredCount == 0 {
                    Text("Ningún extintor coincide con los filtros.")
                        .foregroundStyle(.red)
                }
            }
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
                    if vm.matchesFilter(item) {
                        ExtintorCard(
                            item: $item,
                            readOnly: vm.isReadOnly,
                            onDelete: { vm.removeDetalle(item) },
                            onToggleDescartado: { v in
                                vm.toggleDescartado(localId: item.localId, descartado: v)
                            },
                            onChangeCatalog: {
                                vm.changingCatalogForLocalId = item.localId
                            }
                        )
                    }
                }
            }
            if !vm.isReadOnly {
                Button {
                    if vm.clienteId == nil {
                        vm.errorMessage = "Selecciona un cliente primero."
                    } else {
                        vm.addBlankDetalle()
                    }
                } label: {
                    Label("Agregar extintor", systemImage: "plus.circle.fill")
                }
            }
        } header: {
            HStack {
                Text("Extintores")
                Spacer()
                if vm.hasActiveFilter {
                    Text("\(vm.filteredCount) / \(vm.detalles.count)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(vm.detalles.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var filtrosRow: some View {
        // Solo mostramos los filtros si hay al menos algunos extintores para filtrar
        if vm.detalles.count >= 2 {
            HStack(spacing: 8) {
                Menu {
                    Button("Todas") { vm.filterMarcaId = nil }
                    ForEach(vm.availableMarcas, id: \.0) { (id, name) in
                        Button(name) { vm.filterMarcaId = id }
                    }
                } label: {
                    filterLabel(
                        title: "Marca",
                        value: vm.filterMarcaId.flatMap { id in
                            vm.availableMarcas.first { $0.0 == id }?.1
                        }
                    )
                }

                Menu {
                    Button("Todos") { vm.filterTipoId = nil }
                    ForEach(vm.availableTipos, id: \.0) { (id, name) in
                        Button(name) { vm.filterTipoId = id }
                    }
                } label: {
                    filterLabel(
                        title: "Tipo",
                        value: vm.filterTipoId.flatMap { id in
                            vm.availableTipos.first { $0.0 == id }?.1
                        }
                    )
                }

                Menu {
                    Button("Todas") { vm.filterCapacidadId = nil }
                    ForEach(vm.availableCapacidades, id: \.0) { (id, name) in
                        Button(name) { vm.filterCapacidadId = id }
                    }
                } label: {
                    filterLabel(
                        title: "Cap.",
                        value: vm.filterCapacidadId.flatMap { id in
                            vm.availableCapacidades.first { $0.0 == id }?.1
                        }
                    )
                }

                if vm.hasActiveFilter {
                    Button(role: .destructive) {
                        vm.clearFilters()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func filterLabel(title: String, value: String?) -> some View {
        let isActive = value != nil
        HStack(spacing: 4) {
            Text(value ?? title)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.gray.opacity(0.12))
        .foregroundStyle(isActive ? Color.accentColor : .primary)
        .clipShape(Capsule())
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
    let onChangeCatalog: () -> Void

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
        if !readOnly {
            Button {
                onChangeCatalog()
            } label: {
                Label("Cambiar tipo de extintor", systemImage: "arrow.triangle.2.circlepath")
            }
            .font(.callout)
            .padding(.vertical, 2)
            .buttonStyle(.borderless)
        }
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
                .buttonStyle(.borderless)
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
    var suggestedName: String?
}

/// Construye un nombre de archivo válido a partir del nombre del cliente
/// (preferentemente subEmpresa). Reemplaza espacios y caracteres no aptos
/// para nombres de archivo.
func reportePdfFilename(clienteName: String?) -> String {
    let name = (clienteName ?? "").trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return "Reporte.pdf" }
    let disallowed = CharacterSet(charactersIn: "/\\:*?\"<>|")
    let cleaned = name
        .components(separatedBy: disallowed)
        .joined()
        .replacingOccurrences(of: " ", with: "_")
    return "Reporte_\(cleaned).pdf"
}

private struct ChangingCatalogContext: Identifiable {
    let localId: UUID
    var id: UUID { localId }
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
