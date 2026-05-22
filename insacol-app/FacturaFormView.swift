import SwiftUI

private struct FacturaLineaItem: Identifiable {
    var id = UUID()
    var productoId: Int64?
    var productoNombre: String = ""
    var tipoProducto: String?
    var cantidad: Double = 1
    var precioVenta: Double = 0
    var tasaItbms: String = "01"

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
private final class FacturaFormViewModel {
    var clienteId: Int64?
    var clienteNombre: String = ""
    var fecha: Date = Date()
    var formaPago: MetodoPago = .efectivo
    var retencionItbms: Bool = false
    var observaciones: String = ""
    var descuento: Double = 0
    var lineas: [FacturaLineaItem] = []

    var subtotal: Double { lineas.reduce(0) { $0 + $1.total } }
    var totalItbms: Double { lineas.reduce(0) { $0 + $1.itbmsAmount } }
    var total: Double { subtotal - descuento + totalItbms }

    var isValid: Bool {
        clienteId != nil
        && lineas.contains { $0.productoId != nil && $0.cantidad > 0 }
    }

    init(dto: FacturaDto? = nil) {
        if let dto = dto { loadFrom(dto) }
    }

    func loadFrom(_ dto: FacturaDto) {
        clienteId = dto.clienteId
        clienteNombre = dto.clienteDisplayName
        fecha = dto.fecha?.apiDate ?? Date()
        formaPago = MetodoPago(rawValue: dto.formaPago ?? "") ?? .efectivo
        retencionItbms = (dto.retencionItbms ?? 0) > 0
        observaciones = dto.observaciones ?? ""
        descuento = dto.descuento ?? 0
        lineas = (dto.detalles ?? []).map { d in
            var l = FacturaLineaItem()
            l.productoId = d.productoId
            l.productoNombre = d.productoNombre ?? ""
            l.tipoProducto = d.tipoProducto
            l.cantidad = d.cantidad ?? 1
            l.precioVenta = d.precioVenta ?? 0
            l.tasaItbms = d.tasaItbms ?? "01"
            return l
        }
    }

    func toDto(reporteMantenimientoId: Int64?) -> FacturaDto {
        FacturaDto(
            id: nil,
            clienteId: clienteId,
            clienteEmpresa: nil,
            clienteSubEmpresa: nil,
            serie: nil,
            fecha: fecha.apiDateString,
            subtotal: subtotal,
            descuento: descuento,
            impuestos: totalItbms,
            total: total,
            formaPago: formaPago.rawValue,
            observaciones: observaciones.isEmpty ? nil : observaciones,
            pagado: nil,
            anulada: nil,
            cotizacionOrigenId: nil,
            reporteMantenimientoId: reporteMantenimientoId,
            detalles: lineas.map { l in
                FacturaDetalleDto(
                    id: nil,
                    productoId: l.productoId,
                    productoNombre: l.productoNombre,
                    tipoProducto: l.tipoProducto,
                    cantidad: l.cantidad,
                    precioVenta: l.precioVenta,
                    total: l.total,
                    tasaItbms: l.tasaItbms
                )
            },
            cuentaBancariaId: nil,
            montoPagado: nil,
            fechaPago: nil,
            estadoFe: nil,
            numeroDocumentoFiscal: nil,
            cufe: nil,
            qrUrl: nil,
            retencionItbms: retencionItbms ? 1.0 : 0.0,
            montoPorCobrar: nil
        )
    }
}

struct FacturaFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: FacturaFormViewModel

    let prefilledDto: FacturaDto?
    let reporteMantenimientoId: Int64?
    let onClose: (Bool) -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingClientePicker = false
    @State private var showingProductoPicker: IdentifiableUUID?

    init(prefilledDto: FacturaDto?,
         reporteMantenimientoId: Int64? = nil,
         onClose: @escaping (Bool) -> Void) {
        self.prefilledDto = prefilledDto
        self.reporteMantenimientoId = reporteMantenimientoId
        self.onClose = onClose
        _vm = State(initialValue: FacturaFormViewModel(dto: prefilledDto))
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
                    Toggle("Retención ITBMS", isOn: $vm.retencionItbms)
                    TextField("Observaciones", text: $vm.observaciones, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    ForEach($vm.lineas) { $linea in
                        FacturaLineaFormRow(linea: $linea) {
                            showingProductoPicker = IdentifiableUUID(id: linea.id)
                        }
                    }
                    .onDelete { idx in vm.lineas.remove(atOffsets: idx) }

                    Button {
                        vm.lineas.append(FacturaLineaItem())
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
            .navigationTitle(prefilledDto == nil ? "Nueva factura" : "Confirmar factura")
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
                   ),
                   presenting: errorMessage) { _ in
                Button("OK") { errorMessage = nil }
            } message: { msg in Text(msg) }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let dto = vm.toDto(reporteMantenimientoId: reporteMantenimientoId)
        do {
            _ = try await APIClient.shared.createFactura(dto)
            onClose(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Factura line row

private struct FacturaLineaFormRow: View {
    @Binding var linea: FacturaLineaItem
    let onPickProducto: () -> Void

    @State private var cantidadText: String = ""
    @State private var precioText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPickProducto) {
                HStack {
                    Text(linea.productoNombre.isEmpty ? "Seleccionar producto" : linea.productoNombre)
                        .foregroundStyle(linea.productoNombre.isEmpty ? .secondary : .primary)
                        .lineLimit(linea.productoNombre.isEmpty ? 1 : nil)
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
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(linea.total.currencyString)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            cantidadText = linea.cantidad == 1 ? "1" : String(format: "%.2f", linea.cantidad)
            precioText = linea.precioVenta == 0 ? "" : String(format: "%.2f", linea.precioVenta)
        }
        .onChange(of: linea.precioVenta) { _, v in
            precioText = v == 0 ? "" : String(format: "%.2f", v)
        }
        .onChange(of: linea.cantidad) { _, v in
            cantidadText = v == 1 ? "1" : String(format: "%.2f", v)
        }
    }
}
