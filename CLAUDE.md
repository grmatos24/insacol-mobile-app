# Insacol iOS App — Contexto para Claude

## Stack

- **iOS 17+**, SwiftUI, Swift Concurrency (`async/await`)
- **Patrón**: `@MainActor @Observable final class` ViewModel por vista
- **Backend**: Spring Boot en `http://192.168.1.21:8080`
- **Auth**: JWT guardado en `UserDefaults` vía `AuthManager.shared`
- **Build**: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme insacol-app -destination 'platform=iOS Simulator,id=CCCD8FE0-87E2-4272-AB21-8A2B8C673ECF' build`

---

## Estructura de archivos

```
insacol-app/
├── APIClient.swift          — cliente HTTP + AuthManager + todos los endpoints
├── Models.swift             — todos los DTOs + extensiones Date/String
├── Selectors.swift          — ClienteSelectorView + ProductoSelectorView
├── MainTabView.swift        — 5 tabs + AjustesView
├── LoginView.swift
├── ComercialView.swift      — tab Comercial (picker Facturas | Cotizaciones)
├── FacturasListView.swift   — lista facturas + swipes + filtros + FE
├── FacturaFormView.swift    — form crear factura (3 flujos)
├── CotizacionesListView.swift
├── CotizacionFormView.swift
├── CatalogosView.swift      — tab Catálogos (picker Clientes | Productos | Categorías)
├── ClientesListView.swift
├── ClienteFormView.swift    — con consulta RUC HKA
├── ProductosListView.swift
├── ProductoFormView.swift
├── GastosListView.swift
├── GastoFormView.swift
├── ReportesMantenimientoListView.swift  — con swipe "Crear factura"
├── ReporteMantenimientoFormView.swift
├── CategoriasListView.swift
└── ViewExtensions.swift     — PDFShareSheet, PDFShareItem, currencyString, etc.
```

---

## Navegación

```
Mantenimiento | Comercial | Gastos | Catálogos | Ajustes
```

- `ComercialView` — Picker segmentado: Facturas | Cotizaciones
- `CatalogosView` — Picker segmentado: Clientes | Productos | Categorías
- `AjustesView` — en `MainTabView.swift`

---

## Patrones establecidos

### ViewModel
```swift
@MainActor
@Observable
final class MiListViewModel {
    var items: [Dto] = []
    var isLoading = false
    var errorMessage: String?
    var search: String = ""

    func load() async { ... }
}
```

### Búsqueda con debounce (300ms)
```swift
@State private var searchTask: Task<Void, Never>?

.onChange(of: vm.search) { _, _ in
    searchTask?.cancel()
    searchTask = Task {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }
        await vm.load()
    }
}
```

### Alert con item (delete/confirm)
```swift
.alert("¿Eliminar?",
       isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
       presenting: toDelete) { item in
    Button("Cancelar", role: .cancel) { toDelete = nil }
    Button("Eliminar", role: .destructive) {
        let target = item; toDelete = nil
        Task { await vm.delete(target) }
    }
} message: { _ in Text("Esta acción no se puede deshacer.") }
```

### Sheet con form + callback
```swift
onClose: (Bool) -> Void  // true = guardó, false = canceló
```

### Guard re-entrante en operaciones
```swift
guard !isLoading else { return }
isLoading = true
defer { isLoading = false }
```

---

## Parseo de fechas

El backend devuelve fechas en dos formatos:
- `"2026-05-17"` — solo fecha
- `"2026-05-17T00:00:00.000+00:00"` — ISO 8601 con hora

`String.apiDate` prueba ambos formatos (ver `Models.swift`).  
Mostrar: `date.displayString` → formato `dd/MM/yyyy` en locale `es_PA`.

---

## Facturas — swipes

| Gesto | Condición | Acción |
|-------|-----------|--------|
| → derecha (leading) | `estadoFe != "EMITIDA"` y no anulada | Emitir FE → confirmación → `POST /facturas/{id}/fe/emitir` |
| → derecha (leading) | `estadoFe == "EMITIDA"` | PDF FE → `GET /facturas/{id}/fe/pdf` |
| ← izquierda (trailing) | siempre | PDF interno → `GET /facturas/{id}/pdf` |
| ← izquierda (trailing) | no pagada y no anulada | Anular → confirmación → `PATCH /facturas/anular/{id}` |

### Badge FE en la card
- `EMITIDA` → badge "FE EMITIDA" teal
- `ERROR` → badge "FE ERROR" rojo
- Todo lo demás → sin badge (no mostrar BORRADOR ni PENDIENTE)

---

## Endpoints FE verificados (`192.168.1.21:8080`)

```
POST /facturas/{id}/fe/emitir     — emitir factura electrónica
GET  /facturas/{id}/fe/pdf        — PDF oficial FE
GET  /facturas/{id}/fe/xml        — XML FE (accept: application/xml)
PATCH /facturas/anular/{id}       — anular factura
GET  /facturas/{id}/pdf           — PDF interno
```

---

## Modelos importantes

### `FacturaDto` — campos clave
- `retencionItbms: Double?` — es un monto (no Bool). El toggle en FacturaFormView mapea: load `(val ?? 0) > 0`, save `bool ? 1.0 : 0.0`
- `estadoFe: String?` — `"PENDIENTE"` | `"EMITIDA"` | `"ANULADA"` | `"ERROR"` | nil
- `fecha: String?` — ISO 8601 con hora, parsear con `apiDate`

### `Page<T>` (paginación Spring)
```swift
struct Page<T: Codable>: Codable {
    let content: [T]
    let totalElements: Int?
    let totalPages: Int?
    let number: Int?
    // ...
}
```

---

## Formularios de factura — 3 flujos

1. **Desde cero** — `FacturaFormView(prefilledDto: nil)`
2. **Desde cotización** — `createFacturaFromCotizacion` → navega directo a lista
3. **Desde reporte de mantenimiento** — `getPreFactura(reporteId:)` → `FacturaFormView(prefilledDto: dto, reporteMantenimientoId: id)`

`submit()` siempre llama `createFactura` (nunca update). El `id: nil` es correcto.

---

## Catálogos — Clientes

- `ClienteFormView` tiene consulta RUC via `GET /proveedores/consultar-ruc?ruc=&tipoRuc=`
- Campos obligatorios: `ruc`, `dv`, `empresa`, `subEmpresa`
- `ClienteSelectorView` en `Selectors.swift` — botón "Nuevo cliente" crea inline

---

## Tareas pendientes

- **Diseño visual** — spec en `docs/superpowers/specs/2026-05-20-diseno-visual-ios.md`
  - Opción A: solo AccentColor → `#FFC107`
  - Opción B (recomendada): login oscuro + glass cards + amber ≈ 4h
  - Opción C: navy completo + floating glass ≈ 1 día
  - Paleta marca: primario `#FFC107`, oscuro `#0F172A`

---

## Errores comunes y soluciones

| Error | Causa | Fix |
|-------|-------|-----|
| `DecodingError.typeMismatch Bool` en `retencionItbms` | Backend devuelve Double, modelo tenía Bool | Cambiar a `Double?` en Models.swift |
| Fecha no se muestra en cards | Backend manda ISO 8601 con hora, parser esperaba solo fecha | `ISO8601DateFormatter` como fallback en `String.apiDate` |
| 401 al llamar endpoint → cierra sesión | Ruta incorrecta o IP incorrecta, Spring retorna 401 | Verificar ruta con `curl -s http://192.168.1.21:8080/...` |
| `@ViewBuilder` duplicado | Edit que inserta el atributo sobre uno existente | Revisar antes de editar computed properties con `@ViewBuilder` |
| Compilación falla por tipo-checker | View body muy larga con muchos modificadores | Extraer subviews como `private struct` |
