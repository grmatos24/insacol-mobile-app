# Diseño: Módulo Comercial y Catálogos — iOS App Insacol

**Fecha:** 2026-05-19  
**Estado:** Aprobado

---

## 1. Contexto

La app iOS actualmente cubre Mantenimiento, Gastos y Categorías. Se agrega el módulo Comercial (Facturas + Cotizaciones) y el módulo Catálogos (Clientes + Productos + Categorías), reorganizando la navegación de 4 a 5 tabs.

El backend Spring ya implementa todos los endpoints necesarios. El trabajo es exclusivamente en el cliente iOS.

---

## 2. Navegación

### Tabs (nuevo orden)
```
Mantenimiento | Comercial | Gastos | Catálogos | Ajustes
```

- **Comercial** → `ComercialView` con Picker segmentado: `Facturas | Cotizaciones`
- **Catálogos** → `CatálogosView` con Picker segmentado: `Clientes | Productos | Categorías`
  - Categorías se mueve desde su tab actual a este módulo
- **Ajustes** → sin cambios

### Archivos modificados
- `MainTabView.swift` — reorganizar 5 tabs

---

## 3. Archivos nuevos

```
ComercialView.swift           tab Comercial (wrapper Facturas + Cotizaciones)
FacturasListView.swift        lista de facturas
FacturaFormView.swift         crear factura (3 flujos)
CotizacionesListView.swift    lista de cotizaciones
CotizacionFormView.swift      crear/editar cotización
CatálogosView.swift           tab Catálogos (wrapper)
ClientesListView.swift        lista + CRUD clientes
ClienteFormView.swift         formulario cliente
ProductosListView.swift       lista + CRUD productos
ProductoFormView.swift        formulario producto
```

### Archivos modificados
```
Models.swift      agregar ~6 DTOs + campos FE en ClienteDto
APIClient.swift   agregar ~15 endpoints
Selectors.swift   agregar ClienteSelectorView + ProductoSelectorView
```

---

## 4. Modelos de datos nuevos (`Models.swift`)

### ProductoDto
```swift
struct ProductoDto: Codable, Identifiable, Hashable {
    var id: Int64?
    var nombre: String?
    var precio: Double?
    var tipoProducto: String?   // "PRODUCTO" | "SERVICIO"
}
```

### FacturaDetalleDto
```swift
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
```

### FacturaDto
```swift
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
    var estadoFe: String?       // "PENDIENTE" | "EMITIDA" | "ANULADA" | "ERROR"
    var numeroDocumentoFiscal: String?
    var cufe: String?
    var qrUrl: String?
    var retencionItbms: Bool?
    var montoPorCobrar: Double?
}
```

### CotizacionDetalleDto
```swift
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
```

### CotizacionDto
```swift
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
}
```

### PagoFacturaRequest
```swift
struct PagoFacturaRequest: Codable {
    var montoPagado: Double
    var fechaPago: String
    var cuentaBancariaId: Int64?
    var formaPago: String
}
```

### Extensión ClienteDto (campos FE nuevos)
```swift
var codigoUbicacion: String?
var provinciaFe: String?
var distritoFe: String?
var corregimientoFe: String?
var direccionFe: String?
```

---

## 5. Nuevos endpoints (`APIClient.swift`)

### Clientes
| Método | Path | Función Swift |
|--------|------|---------------|
| GET | `/clientes/search?term=&page=&size=` | `searchClientes(term:page:size:)` |
| POST | `/clientes/save` | `createCliente(_:)` |
| PUT | `/clientes/update/{id}` | `updateCliente(id:dto:)` |
| DELETE | `/clientes/{id}` | `deleteCliente(id:)` |
| GET | `/proveedores/consultar-ruc?ruc=&tipoRuc=` | `consultarRuc(ruc:tipoRuc:)` ya existe → devuelve `ProveedorDto`; el form mapea los campos a `ClienteDto` |

### Productos
| Método | Path | Función Swift |
|--------|------|---------------|
| GET | `/productos/list?page=&size=` | `listProductos(page:size:)` |
| GET | `/productos/search?term=` | `searchProductos(term:)` |
| POST | `/productos/save` | `createProducto(_:)` |
| PUT | `/productos/{id}` | `updateProducto(id:dto:)` |
| DELETE | `/productos/{id}` | `deleteProducto(id:)` |

### Cotizaciones
| Método | Path | Función Swift |
|--------|------|---------------|
| GET | `/cotizaciones/search?term=&page=&size=` | `listCotizaciones(searchTerm:page:size:)` |
| GET | `/cotizaciones/{id}` | `getCotizacion(id:)` |
| POST | `/cotizaciones/save` | `createCotizacion(_:)` |
| PUT | `/cotizaciones/update/{id}` | `updateCotizacion(id:dto:)` |
| DELETE | `/cotizaciones/{id}` | `deleteCotizacion(id:)` |
| GET | `/cotizaciones/{id}/pdf` | `downloadCotizacionPdf(id:)` |

### Facturas
| Método | Path | Función Swift |
|--------|------|---------------|
| GET | `/facturas/search` | `listFacturas(searchTerm:pagado:fechaInicio:fechaFin:page:size:)` |
| GET | `/facturas/{id}` | `getFactura(id:)` |
| POST | `/facturas/save` | `createFactura(_:)` |
| POST | `/facturas/from-cotizacion/{id}` | `createFacturaFromCotizacion(cotizacionId:)` |
| GET | `/reportes-mantenimiento/{id}/pre-factura` | `getPreFactura(reporteId:)` → `FacturaDto` pre-llenado |
| POST | `/facturas/save` | usado también para confirmar la pre-factura del reporte |
| PATCH | `/facturas/anular/{id}` | `anularFactura(id:)` |
| GET | `/facturas/{id}/pdf` | `downloadFacturaPdf(id:)` |
| POST | `/facturas/{id}/emitir-fe` | `emitirFacturaElectronica(id:)` |
| GET | `/facturas/{id}/xml` | `downloadFacturaXml(id:)` |

---

## 6. Clientes CRUD

### `ClientesListView`
- Lista paginada con `searchable` por empresa o subEmpresa
- Fila: nombre (subEmpresa ?? empresa), RUC, badge tipo contribuyente
- Swipe trailing: **Eliminar** (confirmación) / **Editar**
- Botón `+` → `ClienteFormView` en modo crear

### `ClienteFormView`
Secciones:
1. **Empresa** — `empresa`* + `subEmpresa`*
2. **Contacto** — contactoNombre, contactoApellido, correo, teléfono, celular
3. **Fiscal** — `ruc`* + `dv`* + tipoContribuyente + toggle retieneItbms
   - Botón **"Consultar RUC (HKA)"** → pre-llena todos los campos fiscales y FE
4. **Facturación electrónica** — codigoUbicacion, provinciaFe, distritoFe, corregimientoFe, direccionFe

**Campos obligatorios:** ruc, dv, empresa, subEmpresa  
**Validación:** todos los campos obligatorios no vacíos antes de habilitar "Guardar"

### `ClienteSelectorView` (en `Selectors.swift`)
- Sheet de búsqueda por empresa **o** subEmpresa
- Resultado: tap devuelve `ClienteDto` via closure
- Botón "Nuevo cliente" → abre `ClienteFormView` inline y selecciona el recién creado

---

## 7. Productos CRUD

### `ProductosListView`
- Lista con `searchable` por nombre
- Fila: nombre, badge tipo (PRODUCTO/SERVICIO), precio formateado
- Swipe trailing: **Eliminar** (confirmación) / **Editar**
- Botón `+` → `ProductoFormView`

### `ProductoFormView`
- nombre* (TextField)
- Picker tipo: `Producto | Servicio`
- precio de venta* (teclado decimal)

**Validación:** nombre no vacío + precio > 0

### `ProductoSelectorView` (en `Selectors.swift`)
- Sheet de búsqueda por nombre
- Fila: nombre, tipo, precio
- Devuelve `ProductoDto` via closure

---

## 8. Cotizaciones

### `CotizacionesListView`
- Lista paginada con búsqueda por cliente
- Fila: cliente, serie, fecha, total, badge `FACTURADA | PENDIENTE`
- Swipe trailing: **Eliminar** (solo si no facturada, con confirmación), **PDF**
- Swipe leading: **Editar** (solo si no facturada), **Facturar** → `createFacturaFromCotizacion` → navega a `FacturasListView` con snackbar de confirmación (la factura ya quedó guardada, no requiere revisión)
- Botón `+` → `CotizacionFormView`

### `CotizacionFormView`
**Sección cabecera:**
- Cliente (ClienteSelectorView, obligatorio)
- Fecha (DatePicker, default hoy)
- Forma de pago (Picker MetodoPago)
- Observaciones (multilinea)

**Sección líneas:**
- Cada línea: producto (ProductoSelectorView), cantidad, precio unitario (editable), tasa ITBMS (Picker)
- total de línea = cantidad × precioVenta (calculado)
- Botón "Agregar línea"
- Swipe-to-delete en cada línea

**Sección totales (reactivos):**
- Subtotal = suma totales líneas
- Descuento (campo editable, default 0)
- ITBMS = suma impuestos por tasa de cada línea
- Total = subtotal − descuento + ITBMS

**Validación:** cliente + al menos 1 línea con producto y cantidad > 0

**Acción "Facturar"** (modo edición, `facturada == false`): llama `createFacturaFromCotizacion`, navega a la factura.

---

## 9. Facturas

### `FacturasListView`
- Lista con búsqueda, filtro fecha (`FiltersSheet` existente), filtro estado (Todas / Pendientes / Pagadas)
- Fila: cliente, serie, fecha, total, badges `PAGADA|PENDIENTE` + `EMITIDA|BORRADOR|ERROR`
- Swipe trailing: **PDF**, **Anular** (con confirmación, solo si no pagada y no anulada)
- Swipe leading: **Emitir FE** (si `estadoFe != EMITIDA` y no anulada), **Descargar XML** (si `estadoFe == EMITIDA`)
- Botón `+` → `FacturaFormView` (desde cero)

### `FacturaFormView` — 3 flujos de entrada
1. **Desde cero** — formulario vacío
2. **Desde cotización** — recibe `FacturaDto` pre-llenado desde `createFacturaFromCotizacion` (no re-editable el origen)
3. **Desde reporte de mantenimiento** — botón "Crear factura" en `ReportesMantenimientoListView` llama `generarPreFactura(reporteId)` → abre `FacturaFormView` con datos pre-llenados para revisión y confirmación

**Sección cabecera:**
- Cliente (ClienteSelectorView, obligatorio)
- Fecha (DatePicker)
- Forma de pago (Picker MetodoPago)
- Toggle retencionItbms
- Observaciones

**Sección líneas:** idéntica a cotización

**Sección totales:** idéntica a cotización

**Validación:** igual que cotización

### Acciones sobre facturas existentes

| Acción | Condición | Resultado |
|--------|-----------|-----------|
| PDF | siempre | share sheet nativo |
| Anular | no pagada + no anulada | confirmación → `anularFactura` |
| Emitir FE | `estadoFe != EMITIDA` + no anulada | confirmación → `emitirFacturaElectronica` → muestra CUFE o error |
| Descargar XML | `estadoFe == EMITIDA` | share sheet nativo |

---

## 10. Plan de fases

### Fase 1 — Fundación
1. Reorganizar navegación (MainTabView)
2. Agregar DTOs a Models.swift
3. Agregar endpoints a APIClient.swift
4. ClientesListView + ClienteFormView + ClienteSelectorView
5. ProductosListView + ProductoFormView + ProductoSelectorView

### Fase 2 — Documentos comerciales
6. CotizacionesListView + CotizacionFormView
7. FacturasListView + FacturaFormView (3 flujos)
8. Acciones FE (emitir, descargar XML, anular)
9. Integración "Crear factura" en ReportesMantenimientoListView

---

## 11. Lo que queda fuera del alcance iOS

- Registrar pago de factura (queda en la web)
- Anticipos de cliente
- Factura electrónica de anulación
- Envío de FE por correo
- Reportes contables
