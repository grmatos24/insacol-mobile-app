import Foundation
import Observation

enum APIError: LocalizedError {
    case invalidURL
    case http(status: Int, body: String)
    case decoding(Error)
    case transport(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URL inválida"
        case .unauthorized: "Sesión expirada. Inicia sesión nuevamente."
        case .http(let status, let body):
            "Error \(status): \(body.isEmpty ? "sin detalle" : body)"
        case .decoding(let e): "Error al procesar la respuesta: \(e.localizedDescription)"
        case .transport(let e): "Error de red: \(e.localizedDescription)"
        }
    }
}

@Observable
@MainActor
final class AuthManager {
    static let shared = AuthManager()

    private let tokenKey = "insacol.jwt"
    private let userKey = "insacol.user"
    private let nameKey = "insacol.name"
    private let roleKey = "insacol.role"

    private(set) var token: String?
    private(set) var username: String?
    private(set) var name: String?
    private(set) var role: String?

    var isAuthenticated: Bool { token != nil }

    private init() {
        self.token = UserDefaults.standard.string(forKey: tokenKey)
        self.username = UserDefaults.standard.string(forKey: userKey)
        self.name = UserDefaults.standard.string(forKey: nameKey)
        self.role = UserDefaults.standard.string(forKey: roleKey)
    }

    func setSession(token: String, username: String?, name: String?, role: String?) {
        self.token = token
        self.username = username
        self.name = name
        self.role = role
        let d = UserDefaults.standard
        d.set(token, forKey: tokenKey)
        d.set(username, forKey: userKey)
        d.set(name, forKey: nameKey)
        d.set(role, forKey: roleKey)
    }

    func clear() {
        self.token = nil
        self.username = nil
        self.name = nil
        self.role = nil
        let d = UserDefaults.standard
        d.removeObject(forKey: tokenKey)
        d.removeObject(forKey: userKey)
        d.removeObject(forKey: nameKey)
        d.removeObject(forKey: roleKey)
    }
}

@MainActor
final class APIClient {
    static let shared = APIClient()

    var baseURL: URL = URL(string: "https://insacol-api-production.up.railway.app")!
//    var baseURL: URL = URL(string: "http://192.168.1.21:8080")!


    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: cfg)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    // MARK: - Request core

    private func makeRequest(path: String,
                             method: String,
                             query: [URLQueryItem]? = nil,
                             body: Data? = nil,
                             requiresAuth: Bool = true) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                             resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if let query, !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        if requiresAuth, let token = AuthManager.shared.token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest, as: T.Type) async throws -> T {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport(URLError(.badServerResponse))
            }
            if http.statusCode == 401 {
                AuthManager.shared.clear()
                throw APIError.unauthorized
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.http(status: http.statusCode, body: body)
            }
            if T.self == EmptyResponse.self {
                return EmptyResponse() as! T
            }
            do {
                return try decoder.decode(T.self, from: data)
            } catch {
                throw APIError.decoding(error)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error)
        }
    }

    private func performVoid(_ req: URLRequest) async throws {
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport(URLError(.badServerResponse))
            }
            if http.statusCode == 401 {
                AuthManager.shared.clear()
                throw APIError.unauthorized
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.http(status: http.statusCode, body: body)
            }
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error)
        }
    }

    private func downloadData(path: String, accept: String = "application/pdf") async throws -> Data {
        var req = try makeRequest(path: path, method: "GET")
        req.setValue(accept, forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport(URLError(.badServerResponse))
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw APIError.http(status: http.statusCode, body: body)
            }
            return data
        } catch let e as APIError {
            throw e
        } catch {
            throw APIError.transport(error)
        }
    }

    struct EmptyResponse: Decodable {}

    // MARK: - Auth

    func login(username: String, password: String) async throws -> AuthResponse {
        let payload = AuthLoginRequest(username: username, password: password)
        let body = try encoder.encode(payload)
        let req = try makeRequest(path: "auth/login", method: "POST", body: body, requiresAuth: false)
        return try await perform(req, as: AuthResponse.self)
    }

    // MARK: - Gastos

    func listGastos(term: String = "",
                    fechaInicio: Date? = nil,
                    fechaFin: Date? = nil,
                    estadoReembolso: String? = nil,
                    page: Int = 0,
                    size: Int = 20) async throws -> Page<GastoDto> {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "sort", value: "fechaGasto,desc")
        ]
        if let f = fechaInicio { items.append(URLQueryItem(name: "fechaInicio", value: f.apiDateString)) }
        if let f = fechaFin { items.append(URLQueryItem(name: "fechaFin", value: f.apiDateString)) }
        if let e = estadoReembolso, !e.isEmpty {
            items.append(URLQueryItem(name: "estadoReembolso", value: e))
        }
        let req = try makeRequest(path: "gastos/search", method: "GET", query: items)
        return try await perform(req, as: Page<GastoDto>.self)
    }

    func getGasto(id: Int64) async throws -> GastoDto {
        let req = try makeRequest(path: "gastos/\(id)", method: "GET")
        return try await perform(req, as: GastoDto.self)
    }

    func saveGasto(_ dto: GastoDto) async throws -> GastoDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "gastos/save", method: "POST", body: body)
        return try await perform(req, as: GastoDto.self)
    }

    func updateGasto(id: Int64, dto: GastoDto) async throws -> GastoDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "gastos/\(id)", method: "PUT", body: body)
        return try await perform(req, as: GastoDto.self)
    }

    func anularGasto(id: Int64) async throws -> GastoDto {
        let req = try makeRequest(path: "gastos/anular/\(id)", method: "PATCH")
        return try await perform(req, as: GastoDto.self)
    }

    // MARK: - Categorías de gasto

    func listCategorias() async throws -> [CategoriaGastoDto] {
        let req = try makeRequest(path: "gastos/categorias/list", method: "GET")
        return try await perform(req, as: [CategoriaGastoDto].self)
    }

    func saveCategoria(_ dto: CategoriaGastoDto) async throws -> CategoriaGastoDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "gastos/categorias/save", method: "POST", body: body)
        return try await perform(req, as: CategoriaGastoDto.self)
    }

    func updateCategoria(id: Int64, dto: CategoriaGastoDto) async throws -> CategoriaGastoDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "gastos/categorias/\(id)", method: "PUT", body: body)
        return try await perform(req, as: CategoriaGastoDto.self)
    }

    func deleteCategoria(id: Int64) async throws {
        let req = try makeRequest(path: "gastos/categorias/\(id)", method: "DELETE")
        try await performVoid(req)
    }

    // MARK: - Proveedores

    func listProveedores() async throws -> [ProveedorDto] {
        let req = try makeRequest(path: "proveedores", method: "GET")
        return try await perform(req, as: [ProveedorDto].self)
    }

    func consultarRuc(ruc: String, tipoRuc: String) async throws -> ProveedorDto {
        let items = [
            URLQueryItem(name: "ruc", value: ruc),
            URLQueryItem(name: "tipoRuc", value: tipoRuc)
        ]
        let req = try makeRequest(path: "proveedores/consultar-ruc", method: "GET", query: items)
        return try await perform(req, as: ProveedorDto.self)
    }

    func saveProveedor(_ dto: ProveedorDto) async throws -> ProveedorDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "proveedores", method: "POST", body: body)
        return try await perform(req, as: ProveedorDto.self)
    }

    // MARK: - Acreedores

    func listAcreedores() async throws -> [AcreedorDto] {
        let req = try makeRequest(path: "acreedores/list", method: "GET")
        return try await perform(req, as: [AcreedorDto].self)
    }

    // MARK: - Cuentas bancarias

    func listCuentasBancarias() async throws -> [CuentaBancariaDto] {
        let req = try makeRequest(path: "cuentas-bancarias/list", method: "GET")
        return try await perform(req, as: [CuentaBancariaDto].self)
    }

    // MARK: - Clientes

    func listClientes(page: Int = 0, size: Int = 200) async throws -> Page<ClienteDto> {
        let items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)")
        ]
        let req = try makeRequest(path: "clientes/list", method: "GET", query: items)
        return try await perform(req, as: Page<ClienteDto>.self)
    }

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

    // MARK: - Extintores de cliente

    func listExtintoresActivos(clienteId: Int64) async throws -> [ExtintorClienteDto] {
        let req = try makeRequest(path: "extintores-cliente/activos/\(clienteId)", method: "GET")
        return try await perform(req, as: [ExtintorClienteDto].self)
    }

    // MARK: - Catálogo de extintores

    func listExtintoresCatalogo() async throws -> [ExtintorDto] {
        let items = [URLQueryItem(name: "size", value: "1000")]
        let req = try makeRequest(path: "extintores/list", method: "GET", query: items)
        let page = try await perform(req, as: Page<ExtintorDto>.self)
        return page.content
    }

    func listMarcasExtintor() async throws -> [ExtintorMarcaDto] {
        let req = try makeRequest(path: "marcas-extintor/list", method: "GET")
        return try await perform(req, as: [ExtintorMarcaDto].self)
    }

    func listTiposExtintor() async throws -> [ExtintorTipoDto] {
        let req = try makeRequest(path: "tipos-extintor/list", method: "GET")
        return try await perform(req, as: [ExtintorTipoDto].self)
    }

    func listCapacidadesExtintor() async throws -> [ExtintorCapacidadDto] {
        let req = try makeRequest(path: "capacidades-extintor/list", method: "GET")
        return try await perform(req, as: [ExtintorCapacidadDto].self)
    }

    // MARK: - Productos

    func listProductos(page: Int = 0, size: Int = 50) async throws -> Page<ProductoDto> {
        let items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)")
        ]
        let req = try makeRequest(path: "productos/list", method: "GET", query: items)
        return try await perform(req, as: Page<ProductoDto>.self)
    }

    func searchProductos(term: String, page: Int = 0, size: Int = 30) async throws -> [ProductoDto] {
        let items = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)")
        ]
        let req = try makeRequest(path: "productos/search", method: "GET", query: items)
        let p = try await perform(req, as: Page<ProductoDto>.self)
        return p.content
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
        return try await downloadData(path: "cotizaciones/\(id)/pdf")
    }

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

    // Calls a reporte path but returns a pre-filled FacturaDto for review
    func getPreFactura(reporteId: Int64) async throws -> FacturaDto {
        let req = try makeRequest(path: "reportes-mantenimiento/\(reporteId)/pre-factura", method: "GET")
        return try await perform(req, as: FacturaDto.self)
    }

    func anularFactura(id: Int64) async throws -> FacturaDto {
        let req = try makeRequest(path: "facturas/anular/\(id)", method: "PATCH")
        return try await perform(req, as: FacturaDto.self)
    }

    func downloadFacturaPdf(id: Int64) async throws -> Data {
        return try await downloadData(path: "facturas/\(id)/pdf")
    }

    func emitirFacturaElectronica(id: Int64) async throws -> FacturaDto {
        let req = try makeRequest(path: "facturas/\(id)/fe/emitir", method: "POST")
        return try await perform(req, as: FacturaDto.self)
    }

    func downloadFacturaFePdf(id: Int64) async throws -> Data {
        return try await downloadData(path: "facturas/\(id)/fe/pdf")
    }

    func downloadFacturaXml(id: Int64) async throws -> Data {
        return try await downloadData(path: "facturas/\(id)/fe/xml", accept: "application/xml")
    }

    // MARK: - Reportes de mantenimiento

    enum ReporteFilter: String {
        case mesActual = "MES_ACTUAL"
        case proximoMes = "PROXIMO_MES_ACTUAL"
        case todos = "" // sin filterType
    }

    func listReportes(filter: ReporteFilter,
                      searchTerm: String = "",
                      fechaInicio: Date? = nil,
                      fechaFin: Date? = nil,
                      page: Int = 0,
                      size: Int = 30) async throws -> Page<ReporteMantenimientoDto> {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "size", value: "\(size)"),
            URLQueryItem(name: "sort", value: "fechaServicio,desc")
        ]
        if !filter.rawValue.isEmpty {
            items.append(URLQueryItem(name: "filterType", value: filter.rawValue))
        }
        if !searchTerm.isEmpty {
            items.append(URLQueryItem(name: "searchTerm", value: searchTerm))
        }
        if let f = fechaInicio {
            items.append(URLQueryItem(name: "fechaInicio", value: f.apiDateString))
        }
        if let f = fechaFin {
            items.append(URLQueryItem(name: "fechaFin", value: f.apiDateString))
        }
        let req = try makeRequest(path: "reportes-mantenimiento/list", method: "GET", query: items)
        return try await perform(req, as: Page<ReporteMantenimientoDto>.self)
    }

    func getReporte(id: Int64) async throws -> ReporteMantenimientoDto {
        let req = try makeRequest(path: "reportes-mantenimiento/\(id)", method: "GET")
        return try await perform(req, as: ReporteMantenimientoDto.self)
    }

    func saveReporte(_ dto: ReporteMantenimientoDto) async throws -> ReporteMantenimientoDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "reportes-mantenimiento/save", method: "POST", body: body)
        return try await perform(req, as: ReporteMantenimientoDto.self)
    }

    func updateReporte(id: Int64, dto: ReporteMantenimientoDto) async throws -> ReporteMantenimientoDto {
        let body = try encoder.encode(dto)
        let req = try makeRequest(path: "reportes-mantenimiento/\(id)", method: "PUT", body: body)
        return try await perform(req, as: ReporteMantenimientoDto.self)
    }

    func deleteReporte(id: Int64) async throws {
        let req = try makeRequest(path: "reportes-mantenimiento/\(id)", method: "DELETE")
        try await performVoid(req)
    }

    func downloadReportePdf(id: Int64) async throws -> Data {
        return try await downloadData(path: "reportes-mantenimiento/pdf/\(id)")
    }
}
