import SwiftUI

private struct IdentifiableUUID: Identifiable {
    let id: UUID
}

private struct LineaItem: Identifiable {
    var id = UUID()
    var productoId: Int64?
    var productoNombre: String = ""
    var tipoProducto: String?
    var cantidad: Double = 1
    var precioVenta: Double = 0
    var tasaItbms: String = "00"

    var total: Double { cantidad * precioVenta }

    var itbmsAmount: Double {
        let tasa: Double
        switch tasaItbms {
        case "01": tasa = 0.07
        case "02": tasa = 0.10
        case "03": tasa = 0.15
        default: tasa = 0
        }
        return total * tasa
    }
}

@MainActor
@Observable
private final class CotizacionFormViewModel {
    var clienteId: Int64?
    var clienteNombre: String = ""
    var fecha: Date = Date()
    var formaPago: MetodoPago = .efectivo
    var observaciones: String = ""
    var descuento: Double = 0
    var lineas: [LineaItem] = []

    var subtotal: Double { lineas.reduce(0) { $0 + $1.total } }
    var totalItbms: Double { lineas.reduce(0) { $0 + $1.itbmsAmount } }
    var total: Double { subtotal - descuento + totalItbms }

    var isValid: Bool {
        clienteId != nil
        && lineas.contains { $0.productoId != nil && $0.cantidad > 0 }
    }

    init(cotizacion: CotizacionDto? = nil) {
        if let c = cotizacion { loadFrom(c) }
    }

    func loadFrom(_ dto: CotizacionDto) {
        clienteId = dto.clienteId
        clienteNombre = dto.clienteDisplayName
        fecha = dto.fecha?.apiDate ?? Date()
        formaPago = MetodoPago(rawValue: dto.formaPago ?? "") ?? .efectivo
        observaciones = dto.observaciones ?? ""
        descuento = dto.descuento ?? 0
        lineas = (dto.detalles ?? []).map { d in
            var l = LineaItem()
            l.productoId = d.productoId
            l.productoNombre = d.productoNombre ?? ""
            l.tipoProducto = d.tipoProducto
            l.cantidad = d.cantidad ?? 1
            l.precioVenta = d.precioVenta ?? 0
            l.tasaItbms = d.tasaItbms ?? "00"
            return l
        }
    }

    func toDto(existingId: Int64?) -> CotizacionDto {
        CotizacionDto(
            id: existingId,
            clienteId: clienteId,
            fecha: fecha.apiDateString,
            subtotal: subtotal,
            descuento: descuento > 0 ? descuento : nil,
            impuestos: totalItbms,
            total: total,
            formaPago: formaPago.rawValue,
            observaciones: observaciones.isEmpty ? nil : observaciones,
            detalles: lineas.map { l in
                CotizacionDetalleDto(
                    id: nil,
                    productoId: l.productoId,
                    productoNombre: l.productoNombre,
                    tipoProducto: l.tipoProducto,
                    cantidad: l.cantidad,
                    precioVenta: l.precioVenta,
                    total: l.total,
                    tasaItbms: l.tasaItbms
                )
            }
        )
    }
}

struct CotizacionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = CotizacionFormViewModel()

    let existingId: Int64?
    let onClose: (Bool) -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingClientePicker = false
    @State private var showingProductoPicker: IdentifiableUUID?

    init(cotizacion: CotizacionDto?, onClose: @escaping (Bool) -> Void) {
        self.existingId = cotizacion?.id
        self.onClose = onClose
        _vm = State(initialValue: CotizacionFormViewModel(cotizacion: cotizacion))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cliente") {
                    Button {
                        showingClientePicker = true
                    } label: {
                        HStack {
                            Text(vm.clienteNombre.isEmpty ? "Seleccionar cliente *" : vm.clienteNombre)
                                .foregroundStyle(vm.clienteNombre.isEmpty ? .secondary : .primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                }

                Section("Detalle") {
                    DatePicker("Fecha", selection: $vm.fecha, displayedComponents: .date)
                    Picker("Forma de pago", selection: $vm.formaPago) {
                        ForEach(MetodoPago.allCases) { m in
                            Text(m.label).tag(m)
                        }
                    }
                    TextField("Observaciones", text: $vm.observaciones, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach($vm.lineas) { $linea in
                        LineaFormRow(linea: $linea) {
                            showingProductoPicker = IdentifiableUUID(id: linea.id)
                        }
                    }
                    .onDelete { idx in vm.lineas.remove(atOffsets: idx) }

                    Button {
                        vm.lineas.append(LineaItem())
                    } label: {
                        Label("Agregar línea", systemImage: "plus.circle")
                    }
                } header: {
                    Text("Productos")
                }

                Section("Totales") {
                    LabeledContent("Subtotal", value: vm.subtotal.currencyString)
                    HStack {
                        Text("Descuento")
                        Spacer()
                        TextField("0.00", value: $vm.descuento, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    LabeledContent("ITBMS", value: vm.totalItbms.currencyString)
                    LabeledContent("Total", value: vm.total.currencyString)
                        .font(.headline)
                }
            }
            .navigationTitle(existingId == nil ? "Nueva cotización" : "Editar cotización")
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
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("Guardar") }
                    }
                    .disabled(!vm.isValid || isSubmitting)
                }
            }
            .sheet(isPresented: $showingClientePicker) {
                ClienteSelectorView { cliente in
                    vm.clienteId = cliente.id
                    vm.clienteNombre = cliente.displayName
                }
            }
            .sheet(item: $showingProductoPicker) { wrapper in
                ProductoSelectorView { producto in
                    if let idx = vm.lineas.firstIndex(where: { $0.id == wrapper.id }) {
                        vm.lineas[idx].productoId = producto.id
                        vm.lineas[idx].productoNombre = producto.nombre ?? ""
                        vm.lineas[idx].tipoProducto = producto.tipoProducto
                        vm.lineas[idx].precioVenta = producto.precio ?? 0
                    }
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let dto = vm.toDto(existingId: existingId)
        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateCotizacion(id: id, dto: dto)
            } else {
                _ = try await APIClient.shared.createCotizacion(dto)
            }
            onClose(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Line row inside the form

private struct LineaFormRow: View {
    @Binding var linea: LineaItem
    let onPickProducto: () -> Void

    @State private var cantidadText: String = ""
    @State private var precioText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPickProducto) {
                HStack {
                    Text(linea.productoNombre.isEmpty ? "Seleccionar producto" : linea.productoNombre)
                        .foregroundStyle(linea.productoNombre.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption)
                }
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cantidad").font(.caption).foregroundStyle(.secondary)
                    TextField("1", text: $cantidadText)
                        .keyboardType(.decimalPad)
                        .frame(width: 70)
                        .onChange(of: cantidadText) { _, v in
                            linea.cantidad = Double(v.replacingOccurrences(of: ",", with: ".")) ?? linea.cantidad
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Precio").font(.caption).foregroundStyle(.secondary)
                    TextField("0.00", text: $precioText)
                        .keyboardType(.decimalPad)
                        .frame(width: 90)
                        .onChange(of: precioText) { _, v in
                            linea.precioVenta = Double(v.replacingOccurrences(of: ",", with: ".")) ?? linea.precioVenta
                        }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("ITBMS").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $linea.tasaItbms) {
                        ForEach(TasaITBMS.allCases) { t in
                            Text(t.label).tag(t.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 70)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(linea.total.currencyString).font(.subheadline.bold())
                }
            }
        }
        .onChange(of: linea.precioVenta) { _, v in
            precioText = v == 0 ? "" : String(format: "%.2f", v)
        }
        .onChange(of: linea.cantidad) { _, v in
            cantidadText = v == 1 ? "1" : String(format: "%.2f", v)
        }
        .padding(.vertical, 4)
        .onAppear {
            cantidadText = linea.cantidad == 1 ? "1" : String(format: "%.2f", linea.cantidad)
            precioText = linea.precioVenta == 0 ? "" : String(format: "%.2f", linea.precioVenta)
        }
    }
}
