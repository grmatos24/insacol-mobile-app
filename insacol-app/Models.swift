import Foundation

// MARK: - Auth

struct AuthLoginRequest: Codable {
    let username: String
    let password: String
}

struct AuthResponse: Codable {
    let username: String?
    let message: String?
    let jwt: String?
    let status: Bool?
    let role: String?
    let name: String?
}

// MARK: - Método de pago / Tasa ITBMS

enum MetodoPago: String, CaseIterable, Identifiable, Codable {
    case efectivo = "EFECTIVO"
    case transferencia = "TRANSFERENCIA"
    case cheque = "CHEQUE"
    case tarjeta = "TARJETA"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .efectivo: "Efectivo"
        case .transferencia: "Transferencia"
        case .cheque: "Cheque"
        case .tarjeta: "Tarjeta"
        }
    }
}

enum TasaITBMS: String, CaseIterable, Identifiable, Codable {
    case cero = "00"
    case siete = "01"
    case diez = "02"
    case quince = "03"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .cero: "0%"
        case .siete: "7%"
        case .diez: "10%"
        case .quince: "15%"
        }
    }
    var rate: Decimal {
        switch self {
        case .cero: 0
        case .siete: Decimal(string: "0.07")!
        case .diez: Decimal(string: "0.10")!
        case .quince: Decimal(string: "0.15")!
        }
    }
}

// MARK: - Categoría de gasto

struct CategoriaGastoDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombre: String
    var descripcion: String?
    var esCompraMercancia: Bool?
    var esMerma: Bool?
}

// MARK: - Proveedor

struct ProveedorDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var tipoPersona: String?     // "J" o "N"
    var ruc: String?
    var dv: String?
    var razonSocial: String?
    var activo: Bool?
}

// MARK: - Acreedor

struct AcreedorDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombre: String?
    var telefono: String?
    var email: String?
    var activo: Bool?
}

// MARK: - Cuenta bancaria

struct CuentaBancariaDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombreCuenta: String?
    var banco: String?
    var numeroCuenta: String?
    var tipoCuenta: String?
    var saldoActual: Decimal?
}

// MARK: - Gasto

struct GastoDetalleDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var productoId: Int64?
    var productoNombre: String?
    var cantidad: Double?
    var precioUnitario: Double?
    var total: Double?
}

struct GastoDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var proveedor: String?
    var fechaGasto: String?           // "yyyy-MM-dd"
    var categoriaId: Int64?
    var categoriaNombre: String?
    var subtotal: Decimal?
    var impuestos: Decimal?
    var total: Decimal?
    var metodoPago: String?
    var observaciones: String?
    var anulado: Bool?
    var registradoPorNombre: String?
    var proveedorId: Int64?
    var proveedorRazonSocial: String?
    var proveedorRuc: String?
    var proveedorTipoPersona: String?
    var proveedorDv: String?
    var numeroFactura: String?
    var esFondosPersonales: Bool?
    var acreedorId: Int64?
    var acreedorNombre: String?
    var estadoReembolso: String?
    var fechaReembolso: String?
    var cuentaBancariaId: Int64?
    var cuentaBancariaNombre: String?
    var cuentaBancariaReembolsoId: Int64?
    var cuentaBancariaReembolsoNombre: String?
    var detalles: [GastoDetalleDto]?
}

// MARK: - Spring Data Page wrapper

struct Page<T: Codable>: Codable {
    let content: [T]
    let totalElements: Int?
    let totalPages: Int?
    let number: Int?
    let size: Int?
    let first: Bool?
    let last: Bool?
    let empty: Bool?
}

// MARK: - Date helpers

enum DateFormatters {
    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let displayDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_PA")
        f.dateFormat = "dd/MM/yyyy"
        return f
    }()
}

extension Date {
    var apiDateString: String { DateFormatters.isoDate.string(from: self) }
    var displayString: String { DateFormatters.displayDate.string(from: self) }
}

extension String {
    var apiDate: Date? { DateFormatters.isoDate.date(from: self) }
}
