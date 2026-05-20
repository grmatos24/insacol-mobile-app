import SwiftUI

struct ProductoFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingId: Int64?
    @State private var nombre: String
    @State private var tipoProducto: String
    @State private var precioText: String

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let onClose: (Bool) -> Void

    init(producto: ProductoDto?, onClose: @escaping (Bool) -> Void) {
        self.existingId = producto?.id
        _nombre = State(initialValue: producto?.nombre ?? "")
        _tipoProducto = State(initialValue: producto?.tipoProducto ?? "PRODUCTO")
        _precioText = State(initialValue: producto?.precio.map { String(format: "%.2f", $0) } ?? "")
        self.onClose = onClose
    }

    var precioDouble: Double? {
        Double(precioText.replacingOccurrences(of: ",", with: "."))
    }

    var isValid: Bool {
        !nombre.trimmingCharacters(in: .whitespaces).isEmpty
        && (precioDouble ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Producto") {
                    TextField("Nombre *", text: $nombre)
                    Picker("Tipo", selection: $tipoProducto) {
                        Text("Producto").tag("PRODUCTO")
                        Text("Servicio").tag("SERVICIO")
                    }
                    .pickerStyle(.segmented)
                }
                Section("Precio") {
                    TextField("Precio de venta *", text: $precioText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(existingId == nil ? "Nuevo producto" : "Editar producto")
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
                    .disabled(!isValid || isSubmitting)
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func submit() async {
        guard let precio = precioDouble, precio > 0 else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        let dto = ProductoDto(
            id: existingId,
            nombre: nombre.trimmingCharacters(in: .whitespaces),
            precio: precio,
            tipoProducto: tipoProducto
        )
        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateProducto(id: id, dto: dto)
            } else {
                _ = try await APIClient.shared.createProducto(dto)
            }
            onClose(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    ProductoFormView(producto: nil) { _ in }
}
