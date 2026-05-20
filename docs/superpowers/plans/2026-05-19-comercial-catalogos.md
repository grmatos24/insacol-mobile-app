# Comercial y Catálogos Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Clientes + Productos CRUD, Cotizaciones, and Facturas (with FE) to the Insacol iOS app, reorganizing navigation from 4 to 5 tabs.

**Architecture:** Each list view follows the existing `@MainActor @Observable final class` VM pattern with a `NavigationStack`-owned view. `ComercialView` and `CatalogosView` are thin wrappers that embed a segmented `Picker` at the top and switch between child `NavigationStack` views below. Forms follow the `onClose: (Bool) -> Void` pattern from `CategoriaFormView`.

**Tech Stack:** SwiftUI, Swift Concurrency (`async/await`), `@Observable` (iOS 17+), Spring REST API at `http://192.168.40.238:8080`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `Models.swift` | Modify | Add 5 DTOs + FE fields on `ClienteDto` + `Double.currencyString` |
| `APIClient.swift` | Modify | Add 14 new endpoint methods |
| `MainTabView.swift` | Modify | Reorganize 4 → 5 tabs |
| `ComercialView.swift` | Create | Tab wrapper: Picker + FacturasListView / CotizacionesListView |
| `CatalogosView.swift` | Create | Tab wrapper: Picker + ClientesListView / ProductosListView / CategoriasListView |
| `ClientesListView.swift` | Create | Paginated list + delete/edit swipe actions |
| `ClienteFormView.swift` | Create | Create/edit cliente with RUC HKA lookup |
| `ProductosListView.swift` | Create | List + delete/edit swipe actions |
| `ProductoFormView.swift` | Create | Create/edit producto |
| `Selectors.swift` | Modify | Add "Nuevo cliente" button to `ClienteSelectorView`; add `ProductoSelectorView` |
| `CotizacionesListView.swift` | Create | Paginated list + facturar/PDF/delete swipe actions |
| `CotizacionFormView.swift` | Create | Cabecera + line items + reactive totals |
| `FacturasListView.swift` | Create | List + FE/anular/PDF swipe actions |
| `FacturaFormView.swift` | Create | Create from scratch or pre-filled from reporte |
| `ReportesMantenimientoListView.swift` | Modify | Add "Crear factura" swipe action |

---

## Task 1: Add DTOs and currency helper to `Models.swift`

**Files:**
- Modify: `insacol-app/insacol-app/Models.swift`

- [ ] **Step 1: Add FE fields to `ClienteDto` and new DTOs**

In `Models.swift`, extend `ClienteDto` with five new optional fields and append all new DTOs after the existing `Page<T>` definition.

```swift
// In the ClienteDto struct, add after `var retieneItbms: Bool?`:
var codigoUbicacion: String?
var provinciaFe: String?
var distritoFe: String?
var corregimientoFe: String?
var direccionFe: String?
```

Then append at the end of `Models.swift` (before the `// MARK: - Date helpers` section or at the very end):

```swift
// MARK: - Producto

struct ProductoDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombre: String?
    var precio: Double?
    var tipoProducto: String?   // "PRODUCTO" | "SERVICIO"
}

// MARK: - Factura

struct FacturaDetalleDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var productoId: Int64?
    var productoNombre: String?
    var tipoProducto: String?
    var cantidad: Double?
    var precioVenta: Double?
    var total: Double?
    var tasaItbms: String?      // "00" | "01" | "02" | "03"
}

struct FacturaDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var clienteId: Int64?
    var clienteEmpresa: String?
    var clienteSubEmpresa: String?
    var serie: String?
    var fecha: String?
    var subtotal: Double?
    var descuento: Double?
    var impuestos: Double?
    var total: Double?
    var formaPago: String?
    var observaciones: String?
    var pagado: Bool?
    var anulada: Bool?
    var cotizacionOrigenId: Int64?
    var reporteMantenimientoId: Int64?
    var detalles: [FacturaDetalleDto]?
    var cuentaBancariaId: Int64?
    var montoPagado: Double?
    var fechaPago: String?
    var estadoFe: String?               // "PENDIENTE" | "EMITIDA" | "ANULADA" | "ERROR"
    var numeroDocumentoFiscal: String?
    var cufe: String?
    var qrUrl: String?
    var retencionItbms: Bool?
    var montoPorCobrar: Double?

    var clienteDisplayName: String {
        if let s = clienteSubEmpresa, !s.isEmpty { return s }
        if let e = clienteEmpresa, !e.isEmpty { return e }
        return "Cliente #\(clienteId.map(String.init) ?? "-")"
    }
}

// MARK: - Cotización

struct CotizacionDetalleDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var productoId: Int64?
    var productoNombre: String?
    var tipoProducto: String?
    var cantidad: Double?
    var precioVenta: Double?
    var total: Double?
    var tasaItbms: String?
}

struct CotizacionDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var clienteId: Int64?
    var clienteEmpresa: String?
    var clienteSubEmpresa: String?
    var serie: String?
    var fecha: String?
    var subtotal: Double?
    var descuento: Double?
    var impuestos: Double?
    var total: Double?
    var formaPago: String?
    var observaciones: String?
    var facturada: Bool?
    var detalles: [CotizacionDetalleDto]?

    var clienteDisplayName: String {
        if let s = clienteSubEmpresa, !s.isEmpty { return s }
        if let e = clienteEmpresa, !e.isEmpty { return e }
        return "Cliente #\(clienteId.map(String.init) ?? "-")"
    }
}

// MARK: - Currency helper

extension Double {
    var currencyString: String { String(format: "$%.2f", self) }
}
```

- [ ] **Step 2: Build to verify zero errors**

In Xcode press ⌘B. Expected: Build Succeeded with 0 errors.

- [ ] **Step 3: Commit**

```bash
cd /Users/guillermomatos/workspace/Insacol/insacol-app
git add insacol-app/Models.swift
git commit -m "feat: add Producto, Factura, Cotizacion DTOs and FE fields on ClienteDto"
```

---

## Task 2: Add endpoints to `APIClient.swift`

**Files:**
- Modify: `insacol-app/insacol-app/APIClient.swift`

- [ ] **Step 1: Add Clientes CRUD endpoints**

After the `// MARK: - Clientes` section (after `listClientes`), add:

```swift
func searchClientes(term: String = "", page: Int = 0, size: Int = 20) async throws -> Page<ClienteDto> {
    let items = [
        URLQueryItem(name: "term", value: term),
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "size", value: "\(size)")
    ]
    let req = try makeRequest(path: "clientes/search", method: "GET", query: items)
    return try await perform(req, as: Page<ClienteDto>.self)
}

func createCliente(_ dto: ClienteDto) async throws -> ClienteDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "clientes/save", method: "POST", body: body)
    return try await perform(req, as: ClienteDto.self)
}

func updateCliente(id: Int64, dto: ClienteDto) async throws -> ClienteDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "clientes/update/\(id)", method: "PUT", body: body)
    return try await perform(req, as: ClienteDto.self)
}

func deleteCliente(id: Int64) async throws {
    let req = try makeRequest(path: "clientes/\(id)", method: "DELETE")
    try await performVoid(req)
}
```

- [ ] **Step 2: Add Productos endpoints**

After the Clientes section, add a new `// MARK: - Productos` section:

```swift
// MARK: - Productos

func listProductos(page: Int = 0, size: Int = 50) async throws -> Page<ProductoDto> {
    let items = [
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "size", value: "\(size)")
    ]
    let req = try makeRequest(path: "productos/list", method: "GET", query: items)
    return try await perform(req, as: Page<ProductoDto>.self)
}

func searchProductos(term: String) async throws -> [ProductoDto] {
    let items = [URLQueryItem(name: "term", value: term)]
    let req = try makeRequest(path: "productos/search", method: "GET", query: items)
    return try await perform(req, as: [ProductoDto].self)
}

func createProducto(_ dto: ProductoDto) async throws -> ProductoDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "productos/save", method: "POST", body: body)
    return try await perform(req, as: ProductoDto.self)
}

func updateProducto(id: Int64, dto: ProductoDto) async throws -> ProductoDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "productos/\(id)", method: "PUT", body: body)
    return try await perform(req, as: ProductoDto.self)
}

func deleteProducto(id: Int64) async throws {
    let req = try makeRequest(path: "productos/\(id)", method: "DELETE")
    try await performVoid(req)
}
```

- [ ] **Step 3: Add Cotizaciones endpoints**

```swift
// MARK: - Cotizaciones

func listCotizaciones(searchTerm: String = "", page: Int = 0, size: Int = 30) async throws -> Page<CotizacionDto> {
    var items: [URLQueryItem] = [
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "size", value: "\(size)")
    ]
    if !searchTerm.isEmpty {
        items.append(URLQueryItem(name: "term", value: searchTerm))
    }
    let req = try makeRequest(path: "cotizaciones/search", method: "GET", query: items)
    return try await perform(req, as: Page<CotizacionDto>.self)
}

func getCotizacion(id: Int64) async throws -> CotizacionDto {
    let req = try makeRequest(path: "cotizaciones/\(id)", method: "GET")
    return try await perform(req, as: CotizacionDto.self)
}

func createCotizacion(_ dto: CotizacionDto) async throws -> CotizacionDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "cotizaciones/save", method: "POST", body: body)
    return try await perform(req, as: CotizacionDto.self)
}

func updateCotizacion(id: Int64, dto: CotizacionDto) async throws -> CotizacionDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "cotizaciones/update/\(id)", method: "PUT", body: body)
    return try await perform(req, as: CotizacionDto.self)
}

func deleteCotizacion(id: Int64) async throws {
    let req = try makeRequest(path: "cotizaciones/\(id)", method: "DELETE")
    try await performVoid(req)
}

func downloadCotizacionPdf(id: Int64) async throws -> Data {
    var req = try makeRequest(path: "cotizaciones/\(id)/pdf", method: "GET")
    req.setValue("application/pdf", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw APIError.transport(URLError(.badServerResponse))
    }
    if http.statusCode == 401 { AuthManager.shared.clear(); throw APIError.unauthorized }
    if !(200..<300).contains(http.statusCode) {
        throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }
    return data
}
```

- [ ] **Step 4: Add Facturas endpoints**

```swift
// MARK: - Facturas

func listFacturas(searchTerm: String = "",
                  pagado: Bool? = nil,
                  fechaInicio: Date? = nil,
                  fechaFin: Date? = nil,
                  page: Int = 0,
                  size: Int = 30) async throws -> Page<FacturaDto> {
    var items: [URLQueryItem] = [
        URLQueryItem(name: "page", value: "\(page)"),
        URLQueryItem(name: "size", value: "\(size)")
    ]
    if !searchTerm.isEmpty { items.append(URLQueryItem(name: "term", value: searchTerm)) }
    if let p = pagado { items.append(URLQueryItem(name: "pagado", value: "\(p)")) }
    if let f = fechaInicio { items.append(URLQueryItem(name: "fechaInicio", value: f.apiDateString)) }
    if let f = fechaFin { items.append(URLQueryItem(name: "fechaFin", value: f.apiDateString)) }
    let req = try makeRequest(path: "facturas/search", method: "GET", query: items)
    return try await perform(req, as: Page<FacturaDto>.self)
}

func getFactura(id: Int64) async throws -> FacturaDto {
    let req = try makeRequest(path: "facturas/\(id)", method: "GET")
    return try await perform(req, as: FacturaDto.self)
}

func createFactura(_ dto: FacturaDto) async throws -> FacturaDto {
    let body = try encoder.encode(dto)
    let req = try makeRequest(path: "facturas/save", method: "POST", body: body)
    return try await perform(req, as: FacturaDto.self)
}

func createFacturaFromCotizacion(cotizacionId: Int64) async throws -> FacturaDto {
    let req = try makeRequest(path: "facturas/from-cotizacion/\(cotizacionId)", method: "POST")
    return try await perform(req, as: FacturaDto.self)
}

func getPreFactura(reporteId: Int64) async throws -> FacturaDto {
    let req = try makeRequest(path: "reportes-mantenimiento/\(reporteId)/pre-factura", method: "GET")
    return try await perform(req, as: FacturaDto.self)
}

func anularFactura(id: Int64) async throws -> FacturaDto {
    let req = try makeRequest(path: "facturas/anular/\(id)", method: "PATCH")
    return try await perform(req, as: FacturaDto.self)
}

func downloadFacturaPdf(id: Int64) async throws -> Data {
    var req = try makeRequest(path: "facturas/\(id)/pdf", method: "GET")
    req.setValue("application/pdf", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw APIError.transport(URLError(.badServerResponse))
    }
    if http.statusCode == 401 { AuthManager.shared.clear(); throw APIError.unauthorized }
    if !(200..<300).contains(http.statusCode) {
        throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }
    return data
}

func emitirFacturaElectronica(id: Int64) async throws -> FacturaDto {
    let req = try makeRequest(path: "facturas/\(id)/fe/emitir", method: "POST")
    return try await perform(req, as: FacturaDto.self)
}

func downloadFacturaXml(id: Int64) async throws -> Data {
    let req = try makeRequest(path: "facturas/\(id)/fe/xml", method: "GET")
    let (data, response) = try await session.data(for: req)
    guard let http = response as? HTTPURLResponse else {
        throw APIError.transport(URLError(.badServerResponse))
    }
    if http.statusCode == 401 { AuthManager.shared.clear(); throw APIError.unauthorized }
    if !(200..<300).contains(http.statusCode) {
        throw APIError.http(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
    }
    return data
}
```

- [ ] **Step 5: Build to verify zero errors**

Press ⌘B. Expected: Build Succeeded.

- [ ] **Step 6: Commit**

```bash
git add insacol-app/APIClient.swift
git commit -m "feat: add endpoints for Clientes, Productos, Cotizaciones, and Facturas"
```

---

## Task 3: Reorganize navigation — `MainTabView`, `ComercialView`, `CatalogosView`

**Files:**
- Modify: `insacol-app/insacol-app/MainTabView.swift`
- Create: `insacol-app/insacol-app/ComercialView.swift`
- Create: `insacol-app/insacol-app/CatalogosView.swift`

- [ ] **Step 1: Replace `MainTabView.swift` body**

Replace the `TabView` body in `MainTabView` (keep `AjustesView` and the preview intact):

```swift
struct MainTabView: View {
    var body: some View {
        TabView {
            ReportesMantenimientoListView()
                .tabItem {
                    Label("Mantenimiento", systemImage: "wrench.and.screwdriver")
                }

            ComercialView()
                .tabItem {
                    Label("Comercial", systemImage: "doc.text")
                }

            GastosListView()
                .tabItem {
                    Label("Gastos", systemImage: "creditcard")
                }

            CatalogosView()
                .tabItem {
                    Label("Catálogos", systemImage: "books.vertical")
                }

            AjustesView()
                .tabItem {
                    Label("Ajustes", systemImage: "gearshape")
                }
        }
    }
}
```

- [ ] **Step 2: Create `ComercialView.swift`**

Create the file at `insacol-app/insacol-app/ComercialView.swift`:

```swift
import SwiftUI

private enum ComercialTab { case facturas, cotizaciones }

struct ComercialView: View {
    @State private var tab: ComercialTab = .facturas

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Facturas").tag(ComercialTab.facturas)
                Text("Cotizaciones").tag(ComercialTab.cotizaciones)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            switch tab {
            case .facturas:
                FacturasListView()
            case .cotizaciones:
                CotizacionesListView()
            }
        }
    }
}
```

- [ ] **Step 3: Create `CatalogosView.swift`**

Create the file at `insacol-app/insacol-app/CatalogosView.swift`:

```swift
import SwiftUI

private enum CatalogosTab { case clientes, productos, categorias }

struct CatalogosView: View {
    @State private var tab: CatalogosTab = .clientes

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Clientes").tag(CatalogosTab.clientes)
                Text("Productos").tag(CatalogosTab.productos)
                Text("Categorías").tag(CatalogosTab.categorias)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))

            switch tab {
            case .clientes:
                ClientesListView()
            case .productos:
                ProductosListView()
            case .categorias:
                CategoriasListView()
            }
        }
    }
}
```

Note: `FacturasListView`, `CotizacionesListView`, `ClientesListView`, `ProductosListView` are stubs at this point — the project will not build until Tasks 4–8 add those files. Add empty stub files to unblock the build:

```swift
// Temporary stubs — replace in subsequent tasks
import SwiftUI
struct FacturasListView: View { var body: some View { Text("Facturas") } }
struct CotizacionesListView: View { var body: some View { Text("Cotizaciones") } }
struct ClientesListView: View { var body: some View { Text("Clientes") } }
struct ProductosListView: View { var body: some View { Text("Productos") } }
```

Create each as its own file so later tasks replace them cleanly.

- [ ] **Step 4: Build and verify 5 tabs render**

Press ⌘B. Run in simulator. Verify: 5 tabs appear in the correct order. Comercial and Catálogos show stub text.

- [ ] **Step 5: Commit**

```bash
git add insacol-app/MainTabView.swift insacol-app/ComercialView.swift insacol-app/CatalogosView.swift \
        insacol-app/FacturasListView.swift insacol-app/CotizacionesListView.swift \
        insacol-app/ClientesListView.swift insacol-app/ProductosListView.swift
git commit -m "feat: reorganize nav to 5 tabs — Comercial and Catálogos stubs"
```

---

## Task 4: `ClientesListView.swift` + `ClienteFormView.swift`

**Files:**
- Replace stub: `insacol-app/insacol-app/ClientesListView.swift`
- Create: `insacol-app/insacol-app/ClienteFormView.swift`

- [ ] **Step 1: Write `ClientesListView.swift`**

Replace the stub file entirely:

```swift
import SwiftUI

@MainActor
@Observable
final class ClientesListViewModel {
    var clientes: [ClienteDto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""

    var filtered: [ClienteDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return clientes }
        return clientes.filter {
            ($0.empresa?.lowercased().contains(q) ?? false)
            || ($0.subEmpresa?.lowercased().contains(q) ?? false)
            || ($0.ruc?.lowercased().contains(q) ?? false)
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listClientes(size: 500)
            self.clientes = page.content.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ c: ClienteDto) async {
        guard let id = c.id else { return }
        do {
            try await APIClient.shared.deleteCliente(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ClientesListView: View {
    @State private var vm = ClientesListViewModel()
    @State private var showingAdd = false
    @State private var editing: ClienteDto?
    @State private var toDelete: ClienteDto?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.clientes.isEmpty {
                    ProgressView("Cargando...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView(
                        "Sin clientes",
                        systemImage: "person.2.slash",
                        description: Text(vm.search.isEmpty
                            ? "Toca + para agregar el primer cliente."
                            : "No hay resultados para \"\(vm.search)\".")
                    )
                } else {
                    List {
                        ForEach(vm.filtered) { c in
                            ClienteRow(cliente: c)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = c }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        toDelete = c
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                    Button {
                                        editing = c
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Clientes")
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                ClienteFormView(cliente: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { c in
                ClienteFormView(cliente: c) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .alert("¿Eliminar cliente?",
                   isPresented: Binding(
                    get: { toDelete != nil },
                    set: { if !$0 { toDelete = nil } }
                   ),
                   presenting: toDelete) { c in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = c
                    toDelete = nil
                    Task { await vm.delete(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }
}

private struct ClienteRow: View {
    let cliente: ClienteDto

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(cliente.displayName).font(.headline).lineLimit(1)
            HStack(spacing: 8) {
                if let r = cliente.ruc, !r.isEmpty {
                    Text("RUC \(r)\(cliente.dv != nil ? " DV \(cliente.dv!)" : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let t = cliente.tipoContribuyente, !t.isEmpty {
                    Text(t)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Write `ClienteFormView.swift`**

Create new file `insacol-app/insacol-app/ClienteFormView.swift`:

```swift
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
```

Note: `ProveedorDto.dv` is `String?` in the backend response from `consultarRuc`. The existing `ProveedorDto` in `Models.swift` has `var dv: String?`. The form's `dvText` is a String, so map `proveedor.dv` directly to `dvText`.

- [ ] **Step 3: Build to verify zero errors**

Press ⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Manual test**

Run in simulator. Navigate to Catálogos → Clientes. Tap +, fill required fields, save. Verify row appears. Swipe to edit and delete.

- [ ] **Step 5: Commit**

```bash
git add insacol-app/ClientesListView.swift insacol-app/ClienteFormView.swift
git commit -m "feat: add ClientesListView and ClienteFormView with RUC HKA lookup"
```

---

## Task 5: Update `Selectors.swift` — "Nuevo cliente" button + `ProductoSelectorView`

**Files:**
- Modify: `insacol-app/insacol-app/Selectors.swift`

- [ ] **Step 1: Add state and sheet to `ClienteSelectorView` for creating new clients**

In `ClienteSelectorView`, add:
1. `@State private var showingNuevoCliente = false` at the top with the other state vars
2. A toolbar button "Nuevo cliente"
3. A `.sheet` that opens `ClienteFormView`

The new client, once created, should be selected automatically. To accomplish this, change the `createCliente` call's onClose to receive the new dto and call `onPick`.

Replace the entire `ClienteSelectorView` with this updated version:

```swift
struct ClienteSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var clientes: [ClienteDto] = []
    @State private var search: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingNuevoCliente = false
    @State private var createdCliente: ClienteDto?

    let onPick: (ClienteDto) -> Void

    var filtered: [ClienteDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return clientes }
        return clientes.filter { c in
            (c.empresa?.lowercased().contains(q) ?? false)
            || (c.subEmpresa?.lowercased().contains(q) ?? false)
            || (c.ruc?.lowercased().contains(q) ?? false)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && clientes.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView("Sin clientes", systemImage: "person.2.slash")
                } else {
                    List(filtered) { c in
                        Button {
                            onPick(c)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                if let r = c.ruc, !r.isEmpty {
                                    Text("RUC \(r)\(c.dv != nil ? " DV \(c.dv!)" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar cliente")
            .navigationTitle("Seleccionar cliente")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNuevoCliente = true
                    } label: {
                        Label("Nuevo cliente", systemImage: "plus")
                    }
                }
            }
            .task {
                if clientes.isEmpty {
                    isLoading = true
                    defer { isLoading = false }
                    do {
                        let page = try await APIClient.shared.listClientes(size: 500)
                        clientes = page.content.sorted {
                            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                        }
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .onChange(of: createdCliente) { _, new in
                guard let c = new else { return }
                onPick(c)
                dismiss()
            }
            .sheet(isPresented: $showingNuevoCliente) {
                ClienteFormView(cliente: nil) { saved in
                    // ClienteFormView doesn't return the DTO, so reload and pick latest
                    if saved {
                        Task {
                            do {
                                let page = try await APIClient.shared.listClientes(size: 500)
                                let sorted = page.content.sorted {
                                    ($0.id ?? 0) > ($1.id ?? 0)
                                }
                                if let newest = sorted.first {
                                    createdCliente = newest
                                }
                            } catch {}
                        }
                    }
                }
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                   )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
}
```

- [ ] **Step 2: Add `ProductoSelectorView` at the end of `Selectors.swift`**

Append after `ExtintorClientePickerView`:

```swift
// MARK: - Producto Selector

struct ProductoSelectorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search: String = ""
    @State private var resultados: [ProductoDto] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    let onPick: (ProductoDto) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if resultados.isEmpty && !search.isEmpty {
                    ContentUnavailableView(
                        "Sin resultados",
                        systemImage: "magnifyingglass",
                        description: Text("No se encontraron productos para \"\(search)\".")
                    )
                } else if resultados.isEmpty {
                    ContentUnavailableView(
                        "Buscar producto",
                        systemImage: "shippingbox",
                        description: Text("Escribe el nombre del producto.")
                    )
                } else {
                    List(resultados) { p in
                        Button {
                            onPick(p)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.nombre ?? "Producto").font(.headline).foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if let tipo = p.tipoProducto {
                                        Text(tipo == "SERVICIO" ? "Servicio" : "Producto")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.15))
                                            .foregroundStyle(.purple)
                                            .clipShape(Capsule())
                                    }
                                    if let precio = p.precio {
                                        Text(precio.currencyString)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Buscar producto")
            .onChange(of: search) { _, q in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    guard !Task.isCancelled else { return }
                    await runSearch(q)
                }
            }
            .navigationTitle("Seleccionar producto")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
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

    private func runSearch(_ term: String) async {
        guard !term.trimmingCharacters(in: .whitespaces).isEmpty else {
            resultados = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            resultados = try await APIClient.shared.searchProductos(term: term)
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }
}
```

- [ ] **Step 3: Build to verify zero errors**

Press ⌘B. Expected: Build Succeeded.

- [ ] **Step 4: Commit**

```bash
git add insacol-app/Selectors.swift
git commit -m "feat: add Nuevo cliente button to ClienteSelectorView and ProductoSelectorView"
```

---

## Task 6: `ProductosListView.swift` + `ProductoFormView.swift`

**Files:**
- Replace stub: `insacol-app/insacol-app/ProductosListView.swift`
- Create: `insacol-app/insacol-app/ProductoFormView.swift`

- [ ] **Step 1: Write `ProductosListView.swift`**

Replace the stub:

```swift
import SwiftUI

@MainActor
@Observable
final class ProductosListViewModel {
    var productos: [ProductoDto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""

    var filtered: [ProductoDto] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return productos }
        return productos.filter { $0.nombre?.lowercased().contains(q) ?? false }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listProductos(size: 500)
            self.productos = page.content.sorted {
                ($0.nombre ?? "").localizedCaseInsensitiveCompare($1.nombre ?? "") == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ p: ProductoDto) async {
        guard let id = p.id else { return }
        do {
            try await APIClient.shared.deleteProducto(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProductosListView: View {
    @State private var vm = ProductosListViewModel()
    @State private var showingAdd = false
    @State private var editing: ProductoDto?
    @State private var toDelete: ProductoDto?

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.productos.isEmpty {
                    ProgressView("Cargando...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView(
                        "Sin productos",
                        systemImage: "shippingbox",
                        description: Text(vm.search.isEmpty
                            ? "Toca + para agregar el primer producto."
                            : "No hay resultados para \"\(vm.search)\".")
                    )
                } else {
                    List {
                        ForEach(vm.filtered) { p in
                            ProductoRow(producto: p)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = p }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) {
                                        toDelete = p
                                    } label: {
                                        Label("Eliminar", systemImage: "trash")
                                    }
                                    Button {
                                        editing = p
                                    } label: {
                                        Label("Editar", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Productos")
            .searchable(text: $vm.search, prompt: "Buscar producto")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                ProductoFormView(producto: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { p in
                ProductoFormView(producto: p) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .alert("¿Eliminar producto?",
                   isPresented: Binding(
                    get: { toDelete != nil },
                    set: { if !$0 { toDelete = nil } }
                   ),
                   presenting: toDelete) { p in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = p
                    toDelete = nil
                    Task { await vm.delete(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }
}

private struct ProductoRow: View {
    let producto: ProductoDto

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(producto.nombre ?? "Producto").font(.headline)
                if let tipo = producto.tipoProducto {
                    Text(tipo == "SERVICIO" ? "Servicio" : "Producto")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundStyle(.purple)
                        .clipShape(Capsule())
                }
            }
            Spacer()
            if let precio = producto.precio {
                Text(precio.currencyString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
```

- [ ] **Step 2: Write `ProductoFormView.swift`**

Create new file:

```swift
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

    var precioDouble: Double? { Double(precioText.replacingOccurrences(of: ",", with: ".")) }

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
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let dto = ProductoDto(
            id: existingId,
            nombre: nombre.trimmingCharacters(in: .whitespaces),
            precio: precioDouble,
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
```

- [ ] **Step 3: Build to verify zero errors**

Press ⌘B.

- [ ] **Step 4: Manual test**

Navigate to Catálogos → Productos. Create, edit, delete a product.

- [ ] **Step 5: Commit**

```bash
git add insacol-app/ProductosListView.swift insacol-app/ProductoFormView.swift
git commit -m "feat: add ProductosListView and ProductoFormView"
```

---

## Task 7: `CotizacionesListView.swift` + `CotizacionFormView.swift`

**Files:**
- Replace stub: `insacol-app/insacol-app/CotizacionesListView.swift`
- Create: `insacol-app/insacol-app/CotizacionFormView.swift`

- [ ] **Step 1: Write `CotizacionesListView.swift`**

Replace the stub:

```swift
import SwiftUI

@MainActor
@Observable
final class CotizacionesListViewModel {
    var cotizaciones: [CotizacionDto] = []
    var isLoading = false
    var errorMessage: String?
    var successMessage: String?
    var search: String = ""

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listCotizaciones(searchTerm: search, size: 50)
            self.cotizaciones = page.content
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ c: CotizacionDto) async {
        guard let id = c.id else { return }
        do {
            try await APIClient.shared.deleteCotizacion(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func facturar(_ c: CotizacionDto) async {
        guard let id = c.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await APIClient.shared.createFacturaFromCotizacion(cotizacionId: id)
            successMessage = "Factura creada exitosamente. Puedes verla en la pestaña Facturas."
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CotizacionesListView: View {
    @State private var vm = CotizacionesListViewModel()
    @State private var showingAdd = false
    @State private var editing: CotizacionDto?
    @State private var toDelete: CotizacionDto?
    @State private var toFacturar: CotizacionDto?
    @State private var descargandoPdfId: Int64?
    @State private var pdfToShare: PDFShareItem?

    private func descargarPdf(_ c: CotizacionDto) async {
        guard let id = c.id else { return }
        descargandoPdfId = id
        defer { descargandoPdfId = nil }
        do {
            let data = try await APIClient.shared.downloadCotizacionPdf(id: id)
            pdfToShare = PDFShareItem(
                data: data,
                id: id,
                suggestedName: "Cotizacion_\(c.clienteDisplayName.replacingOccurrences(of: " ", with: "_")).pdf"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.cotizaciones.isEmpty {
                    ProgressView("Cargando...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.cotizaciones.isEmpty {
                    ContentUnavailableView(
                        "Sin cotizaciones",
                        systemImage: "doc.text",
                        description: Text("Toca + para crear la primera cotización.")
                    )
                } else {
                    List {
                        ForEach(vm.cotizaciones) { c in
                            CotizacionRow(cotizacion: c)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if c.facturada != true { editing = c }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if c.facturada != true {
                                        Button(role: .destructive) {
                                            toDelete = c
                                        } label: {
                                            Label("Eliminar", systemImage: "trash")
                                        }
                                    }
                                    Button {
                                        Task { await descargarPdf(c) }
                                    } label: {
                                        if descargandoPdfId == c.id {
                                            ProgressView()
                                        } else {
                                            Label("PDF", systemImage: "square.and.arrow.down")
                                        }
                                    }
                                    .tint(.indigo)
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if c.facturada != true {
                                        Button {
                                            editing = c
                                        } label: {
                                            Label("Editar", systemImage: "pencil")
                                        }
                                        .tint(.blue)
                                        Button {
                                            toFacturar = c
                                        } label: {
                                            Label("Facturar", systemImage: "doc.text.fill")
                                        }
                                        .tint(.green)
                                    }
                                }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.load() }
                }
            }
            .navigationTitle("Cotizaciones")
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .onChange(of: vm.search) { _, _ in Task { await vm.load() } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                CotizacionFormView(cotizacion: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $editing) { c in
                CotizacionFormView(cotizacion: c) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(item: $pdfToShare) { item in
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName ?? "Cotizacion.pdf")
            }
            .alert("¿Convertir en factura?",
                   isPresented: Binding(
                    get: { toFacturar != nil },
                    set: { if !$0 { toFacturar = nil } }
                   ),
                   presenting: toFacturar) { c in
                Button("Cancelar", role: .cancel) { toFacturar = nil }
                Button("Facturar") {
                    let target = c
                    toFacturar = nil
                    Task { await vm.facturar(target) }
                }
            } message: { c in
                Text("Se creará una factura para \(c.clienteDisplayName). Esta acción no se puede deshacer.")
            }
            .alert("¿Eliminar cotización?",
                   isPresented: Binding(
                    get: { toDelete != nil },
                    set: { if !$0 { toDelete = nil } }
                   ),
                   presenting: toDelete) { c in
                Button("Cancelar", role: .cancel) { toDelete = nil }
                Button("Eliminar", role: .destructive) {
                    let target = c
                    toDelete = nil
                    Task { await vm.delete(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert("Factura creada",
                   isPresented: Binding(
                    get: { vm.successMessage != nil },
                    set: { if !$0 { vm.successMessage = nil } }
                   )) {
                Button("OK") { vm.successMessage = nil }
            } message: { Text(vm.successMessage ?? "") }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }
}

private struct CotizacionRow: View {
    let cotizacion: CotizacionDto

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(cotizacion.clienteDisplayName).font(.headline).lineLimit(1)
                    Spacer()
                    if let facturada = cotizacion.facturada {
                        let color: Color = facturada ? .green : .orange
                        Text(facturada ? "FACTURADA" : "PENDIENTE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(color.opacity(0.15))
                            .foregroundStyle(color)
                            .clipShape(Capsule())
                    }
                }
                HStack(spacing: 12) {
                    if let s = cotizacion.serie, !s.isEmpty {
                        Text(s).font(.caption).foregroundStyle(.secondary)
                    }
                    if let f = cotizacion.fecha?.apiDate {
                        Label(f.displayString, systemImage: "calendar")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let total = cotizacion.total {
                    Text(total.currencyString).font(.subheadline.bold())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Write `CotizacionFormView.swift`**

Create new file `insacol-app/insacol-app/CotizacionFormView.swift`:

```swift
import SwiftUI

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
final class CotizacionFormViewModel {
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
    @State private var showingProductoPicker: UUID?

    init(cotizacion: CotizacionDto?, onClose: @escaping (Bool) -> Void) {
        self.existingId = cotizacion?.id
        self.onClose = onClose
        if let c = cotizacion {
            let vm = CotizacionFormViewModel()
            vm.loadFrom(c)
            _vm = State(initialValue: vm)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                // Cabecera
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

                // Líneas
                Section {
                    ForEach($vm.lineas) { $linea in
                        LineaFormRow(linea: $linea) {
                            showingProductoPicker = linea.id
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

                // Totales
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
            .sheet(item: $showingProductoPicker) { lineaId in
                ProductoSelectorView { producto in
                    if let idx = vm.lineas.firstIndex(where: { $0.id == lineaId }) {
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
        .padding(.vertical, 4)
        .onAppear {
            cantidadText = linea.cantidad == 1 ? "1" : String(format: "%.2f", linea.cantidad)
            precioText = linea.precioVenta == 0 ? "" : String(format: "%.2f", linea.precioVenta)
        }
    }
}
```

Note: `UUID` conforms to `Identifiable` natively, so `@State private var showingProductoPicker: UUID?` works as a sheet item.

- [ ] **Step 3: Build to verify zero errors**

Press ⌘B.

- [ ] **Step 4: Manual test**

Navigate to Comercial → Cotizaciones. Create a cotización with a client and at least one product line. Verify totals are computed correctly. Save. Swipe to PDF, edit, and facturar.

- [ ] **Step 5: Commit**

```bash
git add insacol-app/CotizacionesListView.swift insacol-app/CotizacionFormView.swift
git commit -m "feat: add CotizacionesListView and CotizacionFormView with line items"
```

---

## Task 8: `FacturasListView.swift` + `FacturaFormView.swift`

**Files:**
- Replace stub: `insacol-app/insacol-app/FacturasListView.swift`
- Create: `insacol-app/insacol-app/FacturaFormView.swift`

- [ ] **Step 1: Write `FacturasListView.swift`**

Replace the stub:

```swift
import SwiftUI

@MainActor
@Observable
final class FacturasListViewModel {
    var facturas: [FacturaDto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""
    var filtroEstado: FiltroEstado = .todas
    var fechaInicio: Date?
    var fechaFin: Date?

    enum FiltroEstado: String, CaseIterable, Identifiable {
        case todas = "Todas"
        case pendientes = "Pendientes"
        case pagadas = "Pagadas"
        var id: String { rawValue }
        var pagado: Bool? {
            switch self {
            case .todas: nil
            case .pendientes: false
            case .pagadas: true
            }
        }
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await APIClient.shared.listFacturas(
                searchTerm: search,
                pagado: filtroEstado.pagado,
                fechaInicio: fechaInicio,
                fechaFin: fechaFin,
                size: 50
            )
            self.facturas = page.content
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func anular(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        do {
            _ = try await APIClient.shared.anularFactura(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emitirFe(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await APIClient.shared.emitirFacturaElectronica(id: id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FacturasListView: View {
    @State private var vm = FacturasListViewModel()
    @State private var showingAdd = false
    @State private var showingFilters = false
    @State private var toAnular: FacturaDto?
    @State private var toEmitirFe: FacturaDto?
    @State private var descargandoPdfId: Int64?
    @State private var descargandoXmlId: Int64?
    @State private var pdfToShare: PDFShareItem?
    @State private var xmlToShare: XMLShareItem?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Estado", selection: Binding(
                    get: { vm.filtroEstado },
                    set: { vm.filtroEstado = $0; Task { await vm.load() } }
                )) {
                    ForEach(FacturasListViewModel.FiltroEstado.allCases) { e in
                        Text(e.rawValue).tag(e)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

                Group {
                    if vm.isLoading && vm.facturas.isEmpty {
                        ProgressView("Cargando...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if vm.facturas.isEmpty {
                        ContentUnavailableView(
                            "Sin facturas",
                            systemImage: "doc.text",
                            description: Text("Toca + para crear la primera factura.")
                        )
                    } else {
                        List {
                            ForEach(vm.facturas) { f in
                                FacturaRow(factura: f)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            Task { await descargarPdf(f) }
                                        } label: {
                                            if descargandoPdfId == f.id {
                                                ProgressView()
                                            } else {
                                                Label("PDF", systemImage: "square.and.arrow.down")
                                            }
                                        }
                                        .tint(.indigo)

                                        if f.pagado != true && f.anulada != true {
                                            Button(role: .destructive) {
                                                toAnular = f
                                            } label: {
                                                Label("Anular", systemImage: "xmark.circle")
                                            }
                                        }
                                    }
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        if f.estadoFe == "EMITIDA" {
                                            Button {
                                                Task { await descargarXml(f) }
                                            } label: {
                                                if descargandoXmlId == f.id {
                                                    ProgressView()
                                                } else {
                                                    Label("XML", systemImage: "doc.badge.arrow.up")
                                                }
                                            }
                                            .tint(.teal)
                                        } else if f.anulada != true {
                                            Button {
                                                toEmitirFe = f
                                            } label: {
                                                Label("Emitir FE", systemImage: "bolt.fill")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .refreshable { await vm.load() }
                    }
                }
            }
            .navigationTitle("Facturas")
            .searchable(text: $vm.search, prompt: "Buscar cliente")
            .onChange(of: vm.search) { _, _ in Task { await vm.load() } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilters = true } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task { await vm.load() }
            .sheet(isPresented: $showingAdd) {
                FacturaFormView(prefilledDto: nil) { saved in
                    if saved { Task { await vm.load() } }
                }
            }
            .sheet(isPresented: $showingFilters) {
                FacturasFiltersSheet(
                    fechaInicio: $vm.fechaInicio,
                    fechaFin: $vm.fechaFin,
                    onApply: { Task { await vm.load() } }
                )
            }
            .sheet(item: $pdfToShare) { item in
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName ?? "Factura.pdf")
            }
            .sheet(item: $xmlToShare) { item in
                PDFShareSheet(data: item.data, suggestedName: item.suggestedName)
            }
            .alert("¿Anular factura?",
                   isPresented: Binding(
                    get: { toAnular != nil },
                    set: { if !$0 { toAnular = nil } }
                   ),
                   presenting: toAnular) { f in
                Button("Cancelar", role: .cancel) { toAnular = nil }
                Button("Anular", role: .destructive) {
                    let target = f; toAnular = nil
                    Task { await vm.anular(target) }
                }
            } message: { _ in Text("Esta acción no se puede deshacer.") }
            .alert("¿Emitir factura electrónica?",
                   isPresented: Binding(
                    get: { toEmitirFe != nil },
                    set: { if !$0 { toEmitirFe = nil } }
                   ),
                   presenting: toEmitirFe) { f in
                Button("Cancelar", role: .cancel) { toEmitirFe = nil }
                Button("Emitir") {
                    let target = f; toEmitirFe = nil
                    Task { await vm.emitirFe(target) }
                }
            } message: { _ in
                Text("Se enviará la factura a la DGI vía HKA. Asegúrate de que los datos estén correctos.")
            }
            .alert("Error",
                   isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                   )) {
                Button("OK") { vm.errorMessage = nil }
            } message: { Text(vm.errorMessage ?? "") }
        }
    }

    private func descargarPdf(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        descargandoPdfId = id
        defer { descargandoPdfId = nil }
        do {
            let data = try await APIClient.shared.downloadFacturaPdf(id: id)
            pdfToShare = PDFShareItem(
                data: data,
                id: id,
                suggestedName: "Factura_\(f.clienteDisplayName.replacingOccurrences(of: " ", with: "_")).pdf"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }

    private func descargarXml(_ f: FacturaDto) async {
        guard let id = f.id else { return }
        descargandoXmlId = id
        defer { descargandoXmlId = nil }
        do {
            let data = try await APIClient.shared.downloadFacturaXml(id: id)
            xmlToShare = XMLShareItem(
                data: data,
                suggestedName: "Factura_\(f.serie ?? String(id)).xml"
            )
        } catch {
            vm.errorMessage = error.localizedDescription
        }
    }
}

// MARK: - XML Share Item

struct XMLShareItem: Identifiable {
    let data: Data
    let suggestedName: String
    var id: String { suggestedName }
}

// MARK: - Factura Row

private struct FacturaRow: View {
    let factura: FacturaDto

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(factura.clienteDisplayName).font(.headline).lineLimit(1)
                Spacer()
                pagoBadge
            }
            HStack(spacing: 8) {
                if let s = factura.serie, !s.isEmpty {
                    Text(s).font(.caption).foregroundStyle(.secondary)
                }
                if let f = factura.fecha?.apiDate {
                    Label(f.displayString, systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
                feBadge
            }
            if let total = factura.total {
                Text(total.currencyString).font(.subheadline.bold())
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var pagoBadge: some View {
        if factura.anulada == true {
            Text("ANULADA")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.red.opacity(0.15))
                .foregroundStyle(.red)
                .clipShape(Capsule())
        } else {
            let pagada = factura.pagado == true
            let color: Color = pagada ? .green : .orange
            Text(pagada ? "PAGADA" : "PENDIENTE")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(color.opacity(0.15))
                .foregroundStyle(color)
                .clipShape(Capsule())
        }
    }

    @ViewBuilder
    private var feBadge: some View {
        let estado = factura.estadoFe ?? "BORRADOR"
        let (label, color): (String, Color) = switch estado {
        case "EMITIDA": ("FE EMITIDA", .teal)
        case "ERROR": ("FE ERROR", .red)
        case "ANULADA": ("FE ANULADA", .gray)
        default: ("BORRADOR", .secondary)
        }
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Filters Sheet

private struct FacturasFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var fechaInicio: Date?
    @Binding var fechaFin: Date?
    let onApply: () -> Void

    @State private var useInicio = false
    @State private var useFin = false
    @State private var localInicio: Date = Date()
    @State private var localFin: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Rango de fechas") {
                    Toggle("Desde", isOn: $useInicio)
                    if useInicio {
                        DatePicker("Fecha inicio", selection: $localInicio, displayedComponents: .date)
                    }
                    Toggle("Hasta", isOn: $useFin)
                    if useFin {
                        DatePicker("Fecha fin", selection: $localFin, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Limpiar filtros") {
                        useInicio = false; useFin = false
                        fechaInicio = nil; fechaFin = nil
                    }
                }
            }
            .navigationTitle("Filtros")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aplicar") {
                        fechaInicio = useInicio ? localInicio : nil
                        fechaFin = useFin ? localFin : nil
                        onApply()
                        dismiss()
                    }
                }
            }
            .onAppear {
                useInicio = fechaInicio != nil; useFin = fechaFin != nil
                if let f = fechaInicio { localInicio = f }
                if let f = fechaFin { localFin = f }
            }
        }
    }
}
```

- [ ] **Step 2: Write `FacturaFormView.swift`**

Create `insacol-app/insacol-app/FacturaFormView.swift`. This form handles creation from scratch and pre-filled from a maintenance report:

```swift
import SwiftUI

@MainActor
@Observable
final class FacturaFormViewModel {
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

    func loadFrom(_ dto: FacturaDto) {
        clienteId = dto.clienteId
        clienteNombre = dto.clienteDisplayName
        fecha = dto.fecha?.apiDate ?? Date()
        formaPago = MetodoPago(rawValue: dto.formaPago ?? "") ?? .efectivo
        retencionItbms = dto.retencionItbms ?? false
        observaciones = dto.observaciones ?? ""
        descuento = dto.descuento ?? 0
        lineas = (dto.detalles ?? []).map { d in
            var l = FacturaLineaItem()
            l.productoId = d.productoId
            l.productoNombre = d.productoNombre ?? ""
            l.tipoProducto = d.tipoProducto
            l.cantidad = d.cantidad ?? 1
            l.precioVenta = d.precioVenta ?? 0
            l.tasaItbms = d.tasaItbms ?? "00"
            return l
        }
    }

    func toDto(existingId: Int64?, reporteMantenimientoId: Int64?) -> FacturaDto {
        FacturaDto(
            id: existingId,
            clienteId: clienteId,
            fecha: fecha.apiDateString,
            subtotal: subtotal,
            descuento: descuento > 0 ? descuento : nil,
            impuestos: totalItbms,
            total: total,
            formaPago: formaPago.rawValue,
            observaciones: observaciones.isEmpty ? nil : observaciones,
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
            retencionItbms: retencionItbms
        )
    }
}

struct FacturaLineaItem: Identifiable {
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

struct FacturaFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm = FacturaFormViewModel()

    let prefilledDto: FacturaDto?
    let reporteMantenimientoId: Int64?
    let onClose: (Bool) -> Void

    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showingClientePicker = false
    @State private var showingProductoPicker: UUID?

    init(prefilledDto: FacturaDto?,
         reporteMantenimientoId: Int64? = nil,
         onClose: @escaping (Bool) -> Void) {
        self.prefilledDto = prefilledDto
        self.reporteMantenimientoId = reporteMantenimientoId
        self.onClose = onClose
        if let dto = prefilledDto {
            let vm = FacturaFormViewModel()
            vm.loadFrom(dto)
            _vm = State(initialValue: vm)
        }
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
                            showingProductoPicker = linea.id
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
            .sheet(item: $showingProductoPicker) { lineaId in
                ProductoSelectorView { producto in
                    if let idx = vm.lineas.firstIndex(where: { $0.id == lineaId }) {
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
        let dto = vm.toDto(existingId: nil, reporteMantenimientoId: reporteMantenimientoId)
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
        .padding(.vertical, 4)
        .onAppear {
            cantidadText = linea.cantidad == 1 ? "1" : String(format: "%.2f", linea.cantidad)
            precioText = linea.precioVenta == 0 ? "" : String(format: "%.2f", linea.precioVenta)
        }
    }
}
```

- [ ] **Step 3: Build to verify zero errors**

Press ⌘B.

- [ ] **Step 4: Manual test**

Navigate to Comercial → Facturas. Tap +. Create a factura from scratch with one product. Save. Verify it appears in the list with PENDIENTE badge and BORRADOR FE badge.

- [ ] **Step 5: Commit**

```bash
git add insacol-app/FacturasListView.swift insacol-app/FacturaFormView.swift
git commit -m "feat: add FacturasListView and FacturaFormView with FE badge and anular/emitir actions"
```

---

## Task 9: "Crear factura" from maintenance report + wire FE flow

**Files:**
- Modify: `insacol-app/insacol-app/ReportesMantenimientoListView.swift`

- [ ] **Step 1: Add state variables to `ReportesMantenimientoListView`**

In `ReportesMantenimientoListView`, add these `@State` variables alongside the existing ones:

```swift
@State private var generandoFacturaId: Int64?
@State private var preFactura: FacturaDto?
@State private var preFacturaReporteId: Int64?
```

- [ ] **Step 2: Add `generarPreFactura` function**

Add this function alongside `descargarPdf` and `iniciarMantenimiento`:

```swift
private func generarPreFactura(_ r: ReporteMantenimientoDto) async {
    guard let id = r.id else { return }
    generandoFacturaId = id
    defer { generandoFacturaId = nil }
    do {
        let dto = try await APIClient.shared.getPreFactura(reporteId: id)
        preFacturaReporteId = id
        preFactura = dto
    } catch {
        vm.errorMessage = error.localizedDescription
    }
}
```

- [ ] **Step 3: Add "Crear factura" swipe action**

In the `swipeActions(edge: .leading)` block of `ReportesMantenimientoListView`, add the "Crear factura" button for reports that are NOT yet facturado. Place it before the existing "Iniciar mantenimiento" button:

```swift
.swipeActions(edge: .leading, allowsFullSwipe: false) {
    // Nuevo: Crear factura
    if r.estado != .facturado {
        Button {
            Task { await generarPreFactura(r) }
        } label: {
            if generandoFacturaId == r.id {
                ProgressView()
            } else {
                Label("Crear factura", systemImage: "doc.text.fill")
            }
        }
        .tint(.green)
    }

    // Existing: Iniciar mantenimiento
    if isFromPreviousYear(r) {
        Button {
            Task { await iniciarMantenimiento(r) }
        } label: {
            if iniciandoMantenimientoId == r.id {
                ProgressView()
            } else {
                Label("Iniciar mantenimiento", systemImage: "wrench.adjustable")
            }
        }
        .tint(.green)
    }

    // Existing: PDF
    Button {
        Task { await descargarPdf(r) }
    } label: {
        if descargandoPdfId == r.id {
            ProgressView()
        } else {
            Label("Descargar PDF", systemImage: "square.and.arrow.down")
        }
    }
    .tint(.indigo)
}
```

- [ ] **Step 4: Add the pre-factura sheet**

Add this `.sheet` modifier alongside the other sheets in `ReportesMantenimientoListView.body`:

```swift
.sheet(item: $preFactura) { dto in
    FacturaFormView(
        prefilledDto: dto,
        reporteMantenimientoId: preFacturaReporteId
    ) { saved in
        preFactura = nil
        preFacturaReporteId = nil
        if saved { Task { await vm.load() } }
    }
}
```

Note: `FacturaDto` must conform to `Identifiable` — it already does via `var id: Int64?`. However, `sheet(item:)` requires `Identifiable`, and `Optional<FacturaDto>` used as `$preFactura` won't work directly with `item:` unless `FacturaDto.id` is non-optional. Use a wrapper:

Replace the `@State private var preFactura: FacturaDto?` approach with a dedicated identifiable wrapper. Add this private struct in `ReportesMantenimientoListView.swift`:

```swift
private struct PreFacturaItem: Identifiable {
    let id: Int64
    let dto: FacturaDto
    let reporteId: Int64
}
```

And change the state to:
```swift
@State private var preFacturaItem: PreFacturaItem?
```

Update `generarPreFactura` to:
```swift
private func generarPreFactura(_ r: ReporteMantenimientoDto) async {
    guard let id = r.id else { return }
    generandoFacturaId = id
    defer { generandoFacturaId = nil }
    do {
        let dto = try await APIClient.shared.getPreFactura(reporteId: id)
        preFacturaItem = PreFacturaItem(
            id: dto.id ?? id,
            dto: dto,
            reporteId: id
        )
    } catch {
        vm.errorMessage = error.localizedDescription
    }
}
```

And the sheet:
```swift
.sheet(item: $preFacturaItem) { item in
    FacturaFormView(
        prefilledDto: item.dto,
        reporteMantenimientoId: item.reporteId
    ) { saved in
        if saved { Task { await vm.load() } }
    }
}
```

Remove the `@State private var preFacturaReporteId: Int64?` since it's now inside the item.

- [ ] **Step 5: Build to verify zero errors**

Press ⌘B.

- [ ] **Step 6: Manual test**

Navigate to Mantenimiento. Find a BORRADOR report. Swipe left and tap "Crear factura". Verify `FacturaFormView` opens pre-filled with the report's data. Confirm and save. Verify the report now shows FACTURADO.

- [ ] **Step 7: Commit**

```bash
git add insacol-app/ReportesMantenimientoListView.swift
git commit -m "feat: add Crear factura from maintenance report via pre-factura endpoint"
```

---

## Self-Review Checklist

- [x] **Spec §6 Clientes**: CRUD + RUC lookup + ClienteSelectorView "Nuevo cliente" → Task 4, Task 5
- [x] **Spec §7 Productos**: CRUD + ProductoSelectorView → Task 6, Task 5
- [x] **Spec §8 Cotizaciones**: List + PDF + Facturar + CotizacionFormView with line items → Task 7
- [x] **Spec §9 Facturas**: List + FE badge + Anular + Emitir FE + Download XML + FacturaFormView → Task 8
- [x] **Spec §9 flow 3**: "Crear factura" from ReportesMantenimientoListView → Task 9
- [x] **Spec §2 Navigation**: 5-tab reorganization → Task 3
- [x] **Spec §4 Models**: All 5 DTOs + FE fields on ClienteDto → Task 1
- [x] **Spec §5 Endpoints**: All 14 new endpoint methods → Task 2
- [x] **Out of scope**: Payment registration NOT included
- [x] **PDF sharing**: Reuses `PDFShareItem` + `PDFShareSheet` defined in `ReporteMantenimientoFormView.swift`
