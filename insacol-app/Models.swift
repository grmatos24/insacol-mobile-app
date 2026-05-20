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

// MARK: - Cliente

struct ClienteDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var empresa: String?
    var subEmpresa: String?
    var contactoNombre: String?
    var contactoApellido: String?
    var correo: String?
    var telefono: String?
    var celular: String?
    var ruc: String?
    var dv: Int?
    var tipoContribuyente: String?
    var retieneItbms: Bool?
    var codigoUbicacion: String?
    var provinciaFe: String?
    var distritoFe: String?
    var corregimientoFe: String?
    var direccionFe: String?

    var displayName: String {
        if let s = subEmpresa, !s.isEmpty { return s }
        if let e = empresa, !e.isEmpty { return e }
        return "Cliente #\(id.map(String.init) ?? "-")"
    }
}

// MARK: - Extintor Cliente

struct ExtintorClienteDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var clienteId: Int64?
    var clienteNombre: String?
    var extintorCatalogoId: Int64?
    var extintorNombre: String?
    var numeroSerie: String?
    var ubicacionHabitual: String?
    var codigoInsacol: String?
    var fechaPh: Int?
    var fechaProxPh: Int?
    var activo: Bool?
}

// MARK: - Extintor catálogo (marca / tipo / capacidad)

struct ExtintorMarcaDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombre: String?
}

struct ExtintorTipoDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombre: String?
}

struct ExtintorCapacidadDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var valor: Double?
    var unidad: String?   // backend usa enum UnidadCapacidad (LBS, KG, ...) — decodificamos como String

    var displayText: String {
        let v: String
        if let valor {
            v = (valor.truncatingRemainder(dividingBy: 1) == 0)
                ? String(Int(valor))
                : String(format: "%.1f", valor)
        } else {
            v = "?"
        }
        return "\(v) \(unidad ?? "")".trimmingCharacters(in: .whitespaces)
    }
}

struct ExtintorDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var marcaId: Int64?
    var tipoId: Int64?
    var capacidadId: Int64?
}

// MARK: - Reporte de mantenimiento

enum EstadoMantenimiento: String, Codable {
    case borrador = "BORRADOR"
    case facturado = "FACTURADO"
}

struct ReporteMantenimientoDetalleDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var extintorClienteId: Int64?
    var extintorCatalogoId: Int64?
    var numeroSerie: String?
    var ubicacionHabitual: String?
    var codigoInsacol: String?
    var fechaPh: Int?
    var fechaProxPh: Int?
    var recargado: Bool?
    var cantidadAgenteUtilizado: Double?
    var pruebaHidrostatica: Bool?
    var cambioManguera: Bool?
    var correa: Bool?
    var manometro: Bool?
    var gancho: Bool?
    var pasador: Bool?
    var descartado: Bool?
    var observaciones: String?
}

struct ReporteMantenimientoDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var clienteId: Int64?
    var clienteEmpresa: String?
    var clienteSubEmpresa: String?
    var fechaServicio: String?           // "yyyy-MM-dd"
    var fechaProximoServicio: String?    // "yyyy-MM-dd"
    var observacionesGenerales: String?
    var estado: EstadoMantenimiento?
    var facturaId: Int64?
    var detalles: [ReporteMantenimientoDetalleDto]?
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
    var tasaItbms: String?      // "00" | "01" | "02" | "03"
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
