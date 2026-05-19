import SwiftUI

@MainActor
@Observable
final class GastoFormViewModel {
    let existingId: Int64?

    // Form fields
    var proveedor: String = ""
    var fechaGasto: Date = Date()
    var categoriaId: Int64?
    var metodoPago: MetodoPago = .efectivo
    var subtotalText: String = ""
    var tasaItbms: TasaITBMS = .cero
    var observaciones: String = ""
    var cuentaBancariaId: Int64?
    var esFondosPersonales: Bool = false
    var acreedorId: Int64?
    var numeroFactura: String = ""

    // RUC mode
    var tieneRuc: Bool = false

    // Autocomplete state
    var proveedorSearch: String = ""

    // DGI lookup state
    var mostrarBuscadorDgi: Bool = false
    var rucInput: String = ""
    var tipoRucInput: String = "J"      // "J" o "N"
    var rucBuscando: Bool = false
    var rucMessage: String?

    // Linked proveedor
    var proveedorVinculado: ProveedorDto?
    var proveedorEsNuevo: Bool = false

    // Dropdown data
    var categorias: [CategoriaGastoDto] = []
    var acreedores: [AcreedorDto] = []
    var cuentas: [CuentaBancariaDto] = []
    var proveedores: [ProveedorDto] = []

    var isSubmitting = false
    var errorMessage: String?
    var savedSuccessfully = false

    init(existing: GastoDto?) {
        self.existingId = existing?.id

        if let g = existing {
            proveedor = g.proveedor ?? ""
            if let dateStr = g.fechaGasto, let d = dateStr.apiDate { fechaGasto = d }
            categoriaId = g.categoriaId
            metodoPago = MetodoPago(rawValue: g.metodoPago ?? "") ?? .efectivo
            if let s = g.subtotal {
                subtotalText = NSDecimalNumber(decimal: s).stringValue
            }
            if let st = g.subtotal, let imp = g.impuestos, st > 0 {
                let rate = NSDecimalNumber(decimal: imp).dividing(by: NSDecimalNumber(decimal: st)).doubleValue
                if rate >= 0.13 { tasaItbms = .quince }
                else if rate >= 0.085 { tasaItbms = .diez }
                else if rate >= 0.05 { tasaItbms = .siete }
                else { tasaItbms = .cero }
            }
            observaciones = g.observaciones ?? ""
            cuentaBancariaId = g.cuentaBancariaId
            esFondosPersonales = g.esFondosPersonales ?? false
            acreedorId = g.acreedorId
            numeroFactura = g.numeroFactura ?? ""
            // Si el gasto tiene proveedorId, queda con RUC y vinculado
            if let pid = g.proveedorId {
                tieneRuc = true
                proveedorVinculado = ProveedorDto(
                    id: pid,
                    tipoPersona: g.proveedorTipoPersona,
                    ruc: g.proveedorRuc,
                    dv: g.proveedorDv,
                    razonSocial: g.proveedorRazonSocial,
                    activo: true
                )
            }
        }
    }

    // MARK: - Derived

    var subtotalDecimal: Decimal {
        Decimal(string: subtotalText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    var impuestosDecimal: Decimal {
        (subtotalDecimal * tasaItbms.rate).rounded(2)
    }

    var totalDecimal: Decimal {
        (subtotalDecimal + impuestosDecimal).rounded(2)
    }

    var proveedoresFiltrados: [ProveedorDto] {
        let q = proveedorSearch.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty {
            return Array(proveedores.prefix(8))
        }
        return proveedores.filter { p in
            (p.razonSocial?.lowercased().contains(q) ?? false)
            || (p.ruc?.lowercased().contains(q) ?? false)
        }.prefix(10).map { $0 }
    }

    var requiereNumeroFactura: Bool { proveedorVinculado != nil }

    var isValid: Bool {
        guard !proveedor.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard categoriaId != nil else { return false }
        guard subtotalDecimal > 0 else { return false }
        if esFondosPersonales && acreedorId == nil { return false }
        if requiereNumeroFactura && numeroFactura.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    // MARK: - Load dropdowns

    func loadDropdowns() async {
        do {
            async let cats = APIClient.shared.listCategorias()
            async let accs = APIClient.shared.listAcreedores()
            async let cnts = APIClient.shared.listCuentasBancarias()
            async let provs = APIClient.shared.listProveedores()
            let (a, b, c, d) = try await (cats, accs, cnts, provs)
            self.categorias = a
            self.acreedores = b
            self.cuentas = c
            self.proveedores = d
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    // MARK: - RUC mode

    func setTieneRuc(_ value: Bool) {
        tieneRuc = value
        mostrarBuscadorDgi = false
        proveedorSearch = ""
        rucInput = ""
        rucMessage = nil
        // Si cambia el modo, limpiamos cualquier vínculo y el campo proveedor
        desvincularProveedor()
        proveedor = ""
    }

    // MARK: - Autocomplete selection

    func seleccionarProveedor(_ p: ProveedorDto) {
        vincular(p)
        if (proveedor.trimmingCharacters(in: .whitespaces)).isEmpty,
           let rs = p.razonSocial {
            proveedor = rs
        }
        proveedorSearch = p.razonSocial ?? ""
    }

    private func vincular(_ p: ProveedorDto) {
        proveedorVinculado = p
        proveedorEsNuevo = (p.id == nil)
        if let rs = p.razonSocial,
           proveedor.trimmingCharacters(in: .whitespaces).isEmpty {
            proveedor = rs
        }
    }

    func desvincularProveedor() {
        proveedorVinculado = nil
        proveedorEsNuevo = false
        numeroFactura = ""
        rucMessage = nil
    }

    // MARK: - DGI lookup

    func consultarRuc() async {
        let ruc = rucInput.trimmingCharacters(in: .whitespaces)
        guard !ruc.isEmpty else { return }
        rucBuscando = true
        rucMessage = nil
        defer { rucBuscando = false }
        let tipoRuc = tipoRucInput == "N" ? "1" : "2"
        do {
            let p = try await APIClient.shared.consultarRuc(ruc: ruc, tipoRuc: tipoRuc)
            vincular(p)
            mostrarBuscadorDgi = false
            rucMessage = p.id == nil
                ? "Proveedor encontrado en DGI. Se guardará al registrar el gasto."
                : "Proveedor encontrado en el sistema."
        } catch {
            rucMessage = error.localizedDescription
        }
    }

    // MARK: - Submit

    func submit() async {
        guard isValid else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        // Si el proveedor vinculado es nuevo (vino de DGI sin id), guardarlo primero
        var linked = proveedorVinculado
        if let p = linked, p.id == nil {
            do {
                let saved = try await APIClient.shared.saveProveedor(
                    ProveedorDto(
                        id: nil,
                        tipoPersona: p.tipoPersona,
                        ruc: p.ruc,
                        dv: p.dv,
                        razonSocial: p.razonSocial,
                        activo: true
                    )
                )
                linked = saved
                proveedorVinculado = saved
                proveedorEsNuevo = false
            } catch {
                errorMessage = "No se pudo guardar el proveedor: \(error.localizedDescription)"
                return
            }
        }

        let dto = GastoDto(
            id: existingId,
            proveedor: proveedor.trimmingCharacters(in: .whitespaces),
            fechaGasto: fechaGasto.apiDateString,
            categoriaId: categoriaId,
            categoriaNombre: nil,
            subtotal: subtotalDecimal,
            impuestos: impuestosDecimal,
            total: totalDecimal,
            metodoPago: metodoPago.rawValue,
            observaciones: observaciones.isEmpty ? nil : observaciones,
            anulado: nil,
            registradoPorNombre: nil,
            proveedorId: linked?.id,
            proveedorRazonSocial: linked?.razonSocial,
            proveedorRuc: linked?.ruc,
            proveedorTipoPersona: linked?.tipoPersona,
            proveedorDv: linked?.dv,
            numeroFactura: requiereNumeroFactura
                ? (numeroFactura.isEmpty ? nil : numeroFactura)
                : nil,
            esFondosPersonales: esFondosPersonales,
            acreedorId: esFondosPersonales ? acreedorId : nil,
            acreedorNombre: nil,
            estadoReembolso: nil,
            fechaReembolso: nil,
            cuentaBancariaId: esFondosPersonales ? nil : cuentaBancariaId,
            cuentaBancariaNombre: nil,
            cuentaBancariaReembolsoId: nil,
            cuentaBancariaReembolsoNombre: nil,
            detalles: nil
        )

        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateGasto(id: id, dto: dto)
            } else {
                _ = try await APIClient.shared.saveGasto(dto)
            }
            savedSuccessfully = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension Decimal {
    func rounded(_ scale: Int) -> Decimal {
        var v = self
        var r = Decimal()
        NSDecimalRound(&r, &v, scale, .plain)
        return r
    }
}

// MARK: - View

struct GastoFormView: View {
    @Environment(\.dismiss) private var dismiss

    @State var vm: GastoFormViewModel
    let onClose: (Bool) -> Void

    init(gasto: GastoDto?, onClose: @escaping (Bool) -> Void) {
        self._vm = State(initialValue: GastoFormViewModel(existing: gasto))
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Form {
                proveedorSection
                detalleSection
                montosSection
                pagoSection
                observacionesSection
            }
            .navigationTitle(vm.existingId == nil ? "Nuevo gasto" : "Editar gasto")
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
                    Button {
                        Task { await vm.submit() }
                    } label: {
                        if vm.isSubmitting { ProgressView() }
                        else { Text("Guardar") }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .task { await vm.loadDropdowns() }
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
                   ),
                   actions: {
                Button("OK", role: .cancel) { vm.errorMessage = nil }
            }, message: {
                Text(vm.errorMessage ?? "")
            })
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var proveedorSection: some View {
        Section("Proveedor") {
            Picker("Tipo", selection: Binding(
                get: { vm.tieneRuc },
                set: { vm.setTieneRuc($0) }
            )) {
                Text("Sin RUC").tag(false)
                Text("Con RUC (DGI)").tag(true)
            }
            .pickerStyle(.segmented)

            if !vm.tieneRuc {
                // Modo simple: solo input de nombre del proveedor
                TextField("Nombre del proveedor", text: $vm.proveedor)
                    .autocorrectionDisabled()
            } else {
                if let p = vm.proveedorVinculado {
                    proveedorChip(p)
                    TextField("Número de factura", text: $vm.numeroFactura)
                        .autocorrectionDisabled()
                    if vm.numeroFactura.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Número de factura requerido.")
                            .font(.caption)
                            .foregroundStyle(Color.red)
                    }
                } else {
                    proveedorAutocomplete
                    if !vm.mostrarBuscadorDgi {
                        Button {
                            vm.mostrarBuscadorDgi = true
                        } label: {
                            Label("No está en el sistema — buscar en DGI por RUC",
                                  systemImage: "magnifyingglass.circle")
                        }
                    } else {
                        dgiLookup
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var proveedorAutocomplete: some View {
        TextField("Buscar por nombre o RUC", text: $vm.proveedorSearch)
            .autocorrectionDisabled()

        let matches = vm.proveedoresFiltrados
        if !matches.isEmpty {
            ForEach(matches) { p in
                Button {
                    vm.seleccionarProveedor(p)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.razonSocial ?? "—")
                            .foregroundStyle(.primary)
                        Text("\(p.tipoPersona ?? "?") · RUC \(p.ruc ?? "—")\(p.dv != nil ? " DV \(p.dv!)" : "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if !vm.proveedorSearch.isEmpty {
            Text("Sin coincidencias.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var dgiLookup: some View {
        Picker("Tipo", selection: $vm.tipoRucInput) {
            Text("Jurídica (J)").tag("J")
            Text("Natural (N)").tag("N")
        }
        .pickerStyle(.segmented)

        HStack {
            TextField("RUC", text: $vm.rucInput)
                .appKeyboard(.numbersAndPunctuation)
                .autocorrectionDisabled()
            Button {
                Task { await vm.consultarRuc() }
            } label: {
                if vm.rucBuscando { ProgressView() }
                else { Image(systemName: "magnifyingglass") }
            }
            .disabled(vm.rucInput.isEmpty || vm.rucBuscando)
        }

        if let msg = vm.rucMessage {
            Text(msg)
                .font(.caption)
                .foregroundStyle(Color.red)
        }

        Button("Cancelar búsqueda en DGI", role: .cancel) {
            vm.mostrarBuscadorDgi = false
            vm.rucInput = ""
            vm.rucMessage = nil
        }
    }

    @ViewBuilder
    private func proveedorChip(_ p: ProveedorDto) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.razonSocial ?? "—")
                    .font(.headline)
                Text("\(p.tipoPersona ?? "?") · RUC \(p.ruc ?? "—")\(p.dv != nil ? " DV \(p.dv!)" : "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if vm.proveedorEsNuevo {
                    Text("Nuevo · se guardará al registrar el gasto")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Button(role: .destructive) {
                vm.desvincularProveedor()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var detalleSection: some View {
        Section("Detalle del gasto") {
            if vm.tieneRuc {
                // En modo "con RUC" el nombre del proveedor lo gestiona la sección de proveedor.
                // Aquí mostramos solo la descripción opcional si quieres complementar (el campo "proveedor" del DTO sigue siendo el texto descriptivo).
                TextField("Descripción / proveedor (texto)", text: $vm.proveedor)
                    .autocorrectionDisabled()
            }
            DatePicker("Fecha", selection: $vm.fechaGasto, displayedComponents: .date)
            Picker("Categoría", selection: $vm.categoriaId) {
                Text("Selecciona...").tag(Int64?.none)
                ForEach(vm.categorias) { cat in
                    Text(cat.nombre).tag(cat.id)
                }
            }
            Picker("Método de pago", selection: $vm.metodoPago) {
                ForEach(MetodoPago.allCases) { mp in
                    Text(mp.label).tag(mp)
                }
            }
        }
    }

    @ViewBuilder
    private var montosSection: some View {
        Section("Montos") {
            HStack {
                Text("Subtotal")
                Spacer()
                TextField("0.00", text: $vm.subtotalText)
                    .appKeyboard(.decimal)
                    .multilineTextAlignment(.trailing)
            }
            Picker("ITBMS", selection: $vm.tasaItbms) {
                ForEach(TasaITBMS.allCases) { t in
                    Text(t.label).tag(t)
                }
            }
            .pickerStyle(.segmented)
            LabeledContent("Impuestos", value: formatMoney(vm.impuestosDecimal))
            LabeledContent("Total", value: formatMoney(vm.totalDecimal))
                .font(.headline)
        }
    }

    @ViewBuilder
    private var pagoSection: some View {
        Section("Pago") {
            Toggle("Pagado con fondos personales", isOn: $vm.esFondosPersonales)
            if vm.esFondosPersonales {
                Picker("Acreedor", selection: $vm.acreedorId) {
                    Text("Selecciona...").tag(Int64?.none)
                    ForEach(vm.acreedores) { a in
                        Text(a.nombre ?? "—").tag(a.id)
                    }
                }
            } else {
                Picker("Cuenta bancaria", selection: $vm.cuentaBancariaId) {
                    Text("Sin asignar").tag(Int64?.none)
                    ForEach(vm.cuentas) { c in
                        Text("\(c.nombreCuenta ?? "—") · \(c.banco ?? "")").tag(c.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var observacionesSection: some View {
        Section("Observaciones") {
            TextField("Notas...", text: $vm.observaciones, axis: .vertical)
                .lineLimit(3...6)
        }
    }
}

#Preview {
    GastoFormView(gasto: nil) { _ in }
}
