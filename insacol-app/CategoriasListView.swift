import SwiftUI

@MainActor
@Observable
final class CategoriasViewModel {
    var categorias: [CategoriaGastoDto] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let list = try await APIClient.shared.listCategorias()
            self.categorias = list.sorted {
                $0.nombre.localizedCaseInsensitiveCompare($1.nombre) == .orderedAscending
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func delete(_ cat: CategoriaGastoDto) async {
        guard let id = cat.id else { return }
        do {
            try await APIClient.shared.deleteCategoria(id: id)
            await load()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }
}

struct CategoriasListView: View {
    @State private var vm = CategoriasViewModel()
    @State private var showingAdd = false
    @State private var editing: CategoriaGastoDto?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.surface.ignoresSafeArea()
                contentView
            }
            .navigationTitle("Categorías")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                            .font(.headline)
                            .foregroundStyle(Theme.navy)
                            .frame(width: 32, height: 32)
                            .background(Theme.amber)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Nueva categoría")
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                CategoriaFormView(categoria: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { cat in
                CategoriaFormView(categoria: cat) { saved in
                    if saved { Task { await vm.load() } }
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

    @ViewBuilder
    private var contentView: some View {
        if vm.isLoading && vm.categorias.isEmpty {
            ProgressView("Cargando...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.categorias.isEmpty {
            ContentUnavailableView(
                "Sin categorías",
                systemImage: "list.bullet.rectangle",
                description: Text("Toca + para crear tu primera categoría.")
            )
        } else {
            List {
                ForEach(vm.categorias) { cat in
                    CategoriaRow(categoria: cat)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = cat }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await vm.delete(cat) }
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                            }
                            Button { editing = cat } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .refreshable { await vm.load() }
        }
    }
}

private struct CategoriaRow: View {
    let categoria: CategoriaGastoDto

    var body: some View {
        BrandCard(padding: 14, radius: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(categoria.nombre)
                            .font(.headline)
                            .foregroundStyle(Theme.navyText)
                            .lineLimit(1)
                        if let d = categoria.descripcion, !d.isEmpty {
                            Text(d)
                                .font(.caption)
                                .foregroundStyle(Theme.textMuted)
                                .lineLimit(2)
                        }
                    }
                    Spacer()
                }

                let hasTags = categoria.esCompraMercancia == true || categoria.esMerma == true
                if hasTags {
                    dottedDivider
                    HStack(spacing: 6) {
                        if categoria.esCompraMercancia == true {
                            Tag(text: "Mercancía", color: Theme.info)
                        }
                        if categoria.esMerma == true {
                            Tag(text: "Merma", color: .orange)
                        }
                    }
                }
            }
        }
    }

    private var dottedDivider: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: .zero)
                p.addLine(to: CGPoint(x: g.size.width, y: 0))
            }
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundColor(Theme.divider)
        }
        .frame(height: 1)
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Categoria Form

struct CategoriaFormView: View {
    @Environment(\.dismiss) private var dismiss

    let existingId: Int64?
    @State private var nombre: String
    @State private var descripcion: String
    @State private var esCompraMercancia: Bool
    @State private var esMerma: Bool

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    let onClose: (Bool) -> Void

    init(categoria: CategoriaGastoDto?, onClose: @escaping (Bool) -> Void) {
        self.existingId = categoria?.id
        _nombre = State(initialValue: categoria?.nombre ?? "")
        _descripcion = State(initialValue: categoria?.descripcion ?? "")
        _esCompraMercancia = State(initialValue: categoria?.esCompraMercancia ?? false)
        _esMerma = State(initialValue: categoria?.esMerma ?? false)
        self.onClose = onClose
    }

    var isValid: Bool { !nombre.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Información") {
                    TextField("Nombre", text: $nombre)
                    TextField("Descripción", text: $descripcion, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("Atributos") {
                    Toggle("Es compra de mercancía", isOn: $esCompraMercancia)
                    Toggle("Es merma", isOn: $esMerma)
                }
            }
            .navigationTitle(existingId == nil ? "Nueva categoría" : "Editar categoría")
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
                   ),
                   actions: {
                Button("OK", role: .cancel) { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        let dto = CategoriaGastoDto(
            id: existingId,
            nombre: nombre.trimmingCharacters(in: .whitespaces),
            descripcion: descripcion.isEmpty ? nil : descripcion,
            esCompraMercancia: esCompraMercancia,
            esMerma: esMerma
        )
        do {
            if let id = existingId {
                _ = try await APIClient.shared.updateCategoria(id: id, dto: dto)
            } else {
                _ = try await APIClient.shared.saveCategoria(dto)
            }
            onClose(true)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    CategoriasListView()
}
