import SwiftUI

struct ClienteFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingId: Int64?
    @State private var empresa: String
    @State private var subEmpresa: String
    @State private var contactoNombre: String
    @State private var contactoApellido: String
    @State private var correo: String
    @State private var telefono: String
    @State private var celular: String
    @State private var ruc: String
    @State private var dvText: String
    @State private var tipoContribuyente: String
    @State private var retieneItbms: Bool
    @State private var codigoUbicacion: String
    @State private var provinciaFe: String
    @State private var distritoFe: String
    @State private var corregimientoFe: String
    @State private var direccionFe: String

    @State private var isSubmitting = false
    @State private var isConsultandoRuc = false
    @State private var errorMessage: String?

    let onClose: (Bool) -> Void

    init(cliente: ClienteDto?, onClose: @escaping (Bool) -> Void) {
        self.existingId = cliente?.id
        _empresa = State(initialValue: cliente?.empresa ?? "")
        _subEmpresa = State(initialValue: cliente?.subEmpresa ?? "")
        _contactoNombre = State(initialValue: cliente?.contactoNombre ?? "")
        _contactoApellido = State(initialValue: cliente?.contactoApellido ?? "")
        _correo = State(initialValue: cliente?.correo ?? "")
        _telefono = State(initialValue: cliente?.telefono ?? "")
        _celular = State(initialValue: cliente?.celular ?? "")
        _ruc = State(initialValue: cliente?.ruc ?? "")
        _dvText = State(initialValue: cliente?.dv.map(String.init) ?? "")
        _tipoContribuyente = State(initialValue: cliente?.tipoContribuyente ?? "")
        _retieneItbms = State(initialValue: cliente?.retieneItbms ?? false)
        _codigoUbicacion = State(initialValue: cliente?.codigoUbicacion ?? "")
        _provinciaFe = State(initialValue: cliente?.provinciaFe ?? "")
        _distritoFe = State(initialValue: cliente?.distritoFe ?? "")
        _corregimientoFe = State(initialValue: cliente?.corregimientoFe ?? "")
        _direccionFe = State(initialValue: cliente?.direccionFe ?? "")
        self.onClose = onClose
    }

    var isValid: Bool {
        !ruc.trimmingCharacters(in: .whitespaces).isEmpty
        && !dvText.trimmingCharacters(in: .whitespaces).isEmpty
        && !empresa.trimmingCharacters(in: .whitespaces).isEmpty
        && !subEmpresa.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Empresa") {
                    TextField("Empresa *", text: $empresa)
                    TextField("Sub-empresa *", text: $subEmpresa)
                }

                Section("Contacto") {
                    TextField("Nombre contacto", text: $contactoNombre)
                    TextField("Apellido contacto", text: $contactoApellido)
                    TextField("Correo", text: $correo)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Teléfono", text: $telefono)
                        .keyboardType(.phonePad)
                    TextField("Celular", text: $celular)
                        .keyboardType(.phonePad)
                }

                Section("Fiscal") {
                    TextField("RUC *", text: $ruc)
                        .keyboardType(.numberPad)
                    TextField("DV *", text: $dvText)
                        .keyboardType(.numberPad)
                    TextField("Tipo contribuyente", text: $tipoContribuyente)
                    Toggle("Retiene ITBMS", isOn: $retieneItbms)
                    Button {
                        Task { await consultarRuc() }
                    } label: {
                        if isConsultandoRuc {
                            HStack {
                                ProgressView()
                                Text("Consultando RUC...")
                            }
                        } else {
                            Label("Consultar RUC (HKA)", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(ruc.trimmingCharacters(in: .whitespaces).isEmpty || isConsultandoRuc)
                }

                Section("Facturación electrónica") {
                    TextField("Código ubicación", text: $codigoUbicacion)
                    TextField("Provincia", text: $provinciaFe)
                    TextField("Distrito", text: $distritoFe)
                    TextField("Corregimiento", text: $corregimientoFe)
                    TextField("Dirección", text: $direccionFe, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(existingId == nil ? "Nuevo cliente" : "Editar cliente")
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
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func consultarRuc() async {
        isConsultandoRuc = true
        defer { isConsultandoRuc = false }
        do {
            // consultarRuc returns ProveedorDto; ProveedorDto.dv is String?
            let proveedor = try await APIClient.shared.consultarRuc(
                ruc: ruc.trimmingCharacters(in: .whitespaces),
                tipoRuc: "N"
            )
            if let razon = proveedor.razonSocial, !razon.isEmpty {
                empresa = razon
                if subEmpresa.isEmpty { subEmpresa = razon }
            }
            if let d = proveedor.dv { dvText = d }
            if let tipo = proveedor.tipoPersona { tipoContribuyente = tipo }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let dto = ClienteDto(
            id: existingId,
            empresa: empresa.trimmingCharacters(in: .whitespaces),
            subEmpresa: subEmpresa.trimmingCharacters(in: .whitespaces),
            contactoNombre: contactoNombre.isEmpty ? nil : contactoNombre,
            contactoApellido: contactoApellido.isEmpty ? nil : contactoApellido,
            correo: correo.isEmpty ? nil : correo,
            telefono: telefono.isEmpty ? nil : telefono,
            celular: celular.isEmpty ? nil : celular,
            ruc: ruc.trimmingCharacters(in: .whitespaces),
            dv: Int(dvText.trimmingCharacters(in: .whitespaces)),
            tipoContribuyente: tipoContribuyente.isEmpty ? nil : tipoContribuyente,
            retieneItbms: retieneItbms,
            codigoUbicacion: codigoUbicacion.isEmpty ? nil : codigoUbicacion,
            provinciaFe: provinciaFe.isEmpty ? nil : provinciaFe,
            distritoFe: distritoFe.isEmpty ? nil : distritoFe,
            corregimientoFe: corregimientoFe.isEmpty ? nil : corregimientoFe,
            direccionFe: direccionFe.isEmpty ? nil : direccionFe
        )
        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateCliente(id: id, dto: dto)
            } else {
                _ = try await APIClient.shared.createCliente(dto)
            }
            onClose(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
