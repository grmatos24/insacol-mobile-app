# Insacol iOS — Rediseño dirección B (Field First)

Handoff para Claude Code. **NO** reescribir arquitectura ni lógica — solo refactor visual de
`ReportesMantenimientoListView` y `FacturaDetailView`, más nuevos tokens y componentes
compartidos en `Theme.swift` / `DesignSystem.swift`.

La pantalla **Inicio (Home/Dashboard)** se implementa después; ignorarla por ahora.

---

## 1 · Principios visuales

| Principio | Decisión |
|---|---|
| **Tema** | Claro siempre. Fondo cálido `#FAFAF7`, no `systemGroupedBackground`. |
| **Cards** | Blancas, radio 16–18, borde `1px rgba(60,60,67,0.18)`. **NO** `.ultraThinMaterial / glassCard()` en estas dos vistas. |
| **Tap targets** | Mínimo 44pt. Botones inline en cards ≥ 32pt vertical. |
| **Tipografía** | Sistema. Headlines `font(.title2.bold())`, body `.subheadline`, captions `.caption`. Apoyarse en `letterSpacing` solo en labels en mayúsculas. |
| **Color de marca** | `Theme.amberDeep` (`#F59E0B`) para acentos y CTAs primarios. `Theme.navy` solo para superficies oscuras destacadas (panel de totales). Amber base sigue siendo `#FFC107`. |
| **Status semantics** | Verde `.green` = pagado/facturado/completado. Amber = pendiente/borrador. Rojo = anulado/vencido. Azul `.blue` = FE emitida. |
| **Acciones** | Las acciones primarias salen del swipe a la cara visible de la card (botones inline). Mantener swipe actions para acciones secundarias. |
| **Densidad** | Más respiración. `padding 14` interno en cards, `gap 10–12` entre cards. |

---

## 2 · Cambios en `Theme.swift`

Reemplazar el enum `Theme` y añadir tokens nuevos. Mantener la extensión `Color(hex:)` y `StatusBadge` existentes.

Ver `Theme.swift` adjunto en esta carpeta.

---

## 3 · Componentes nuevos — `DesignSystem.swift`

Crear archivo nuevo `DesignSystem.swift` con:

- `StatStrip` — fila de 3 columnas con número grande + label pequeño en mayúsculas.
- `StatCell` — celda usada por `StatStrip` (también utilizable suelta).
- `BrandCard` — wrapper de card blanca con borde sutil. Reemplaza llamadas a `.glassCard()` en estas vistas.
- `InlineActionPill` — botón pill compacto para acciones dentro de una card (PDF, Facturar).
- `BigCTAButton` — botón ancho de acción principal (Registrar pago).
- `TotalSummaryCard` — card navy oscura para sección "Totales" en factura.
- `SectionLabel` — label en mayúsculas con tracking, para "PRODUCTOS · 4" etc.

Ver `DesignSystem.swift` adjunto.

---

## 4 · `ReportesMantenimientoListView.swift`

**Mantener intacto:**
- `ReportesMantenimientoListViewModel` y toda su lógica.
- **`Picker` segmentado con `Mes actual` / `Programados` / `Todos`** — NO eliminar. Solo cambia su contexto (queda arriba del nuevo `StatStrip`).
- `FiltersSheet`, sheets de PDF/factura, alerts.
- Swipe actions (mover acciones secundarias ahí).
- `task`, `searchable`, `onChange(of: vm.search)`.

**Cambiar el body de `ReportesMantenimientoListView`:**

1. Cambiar fondo a `Theme.surface` (`#FAFAF7`) con `.scrollContentBackground(.hidden)`.
2. **Mantener el `Picker` segmentado de filtros** (Mes actual / Programados / Todos) en su posición actual — arriba de todo.
3. Insertar **`StatStrip`** justo debajo del `Picker` segmentado: 3 stats — *Completados*, *Borradores*, *Vencidos*. Computar desde `vm.reportes`.
4. Reemplazar `ReporteRow` por **`ReporteCardRow`** (ver código). Características:
   - Header: nombre cliente + status badge a la derecha.
   - Fecha servicio + próx fecha como caption gris.
   - Divider punteado.
   - Footer: icono flame + "N extintores" a la izquierda; 2 botones pill a la derecha (**PDF** y **Facturar** si no está facturado).
4. La lista usa `BrandCard` (no `glassCard`). `listRowBackground(.clear)`, `listRowSeparator(.hidden)`, `listRowInsets` con 10 vertical.
5. Botón `+` del toolbar pasa a un círculo navy 44pt (en lugar del icono pelado).

---

## 5 · `FacturaDetailView` en `FacturasListView.swift`

**Mantener intacto:**
- ViewModel `FacturasListViewModel` y toda la lógica de `FacturasListView` (lista, búsqueda, filtros, swipe actions).
- Estados, alerts, sheets de FE/PDF.
- `task { ... }` que carga detalles si vienen vacíos.

**Cambiar el body de `FacturaDetailView`:**

Reorganizar de `List` con `Section`s a un `ScrollView` con `VStack(spacing: 12)` y `BrandCard`s. Estructura nueva:

1. **Cliente header** (sin card, padding lateral):
   - Eyebrow: "CLIENTE" en mayúsculas, gris, caption.
   - `clienteDisplayName` en `font(.title.bold())` con `letterSpacing(-0.5)`.
   - Línea de metadata: `fecha · serie · numeroDocumentoFiscal` (mono para NDF).
2. **Status row** (sin card): badges horizontales — *PENDIENTE/PAGADA/ANULADA* + *FE EMITIDA/FE ERROR*. Usar el `StatusBadge` existente pero mismo tamaño.
3. **`BrandCard` "Productos"** — lista de detalles con divider entre items. Cada item: nombre (subheadline.bold), `N × $precio · ITBMS X%` (caption gris), total a la derecha en bold.
4. **`TotalSummaryCard` "Totales"** — fondo navy `#0F172A`, texto blanco. Subtotal, ITBMS, descuento si > 0, retención si > 0, todos en gris `white.opacity(0.6)`. Divider con `white.opacity(0.15)`. Total: `$XX.XX` grande en `Theme.amber` (`#FFC107`).
5. **`BigCTAButton`** verde con texto **"Registrar pago"** — solo si `factura.pagado != true && factura.anulada != true`. Onclick: presentar sheet de registro de pago (placeholder por ahora — Claude Code puede dejar `// TODO: presentar sheet de pago`).

Toolbar igual (PDF y FE PDF).

Ver `FacturaDetailView.swift` adjunto.

---

## 6 · Checklist final

- [ ] `Theme.swift` actualizado con `Theme.surface`, `Theme.navyText`, `Theme.cardBorder`, `Theme.success`, `Theme.danger`, `Theme.warning`.
- [ ] `DesignSystem.swift` creado con los 7 componentes.
- [ ] `ReportesMantenimientoListView.swift` — body refactorizado, `ReporteCardRow` nuevo, stat strip insertada, ViewModel intacto.
- [ ] `FacturasListView.swift` — solo `FacturaDetailView` refactorizada, `FacturasListView` body sin cambios visuales mayores (puede mantenerse igual si no da tiempo, pero idealmente `FacturaRow` también pasa al nuevo estilo de card).
- [ ] `.glassCard()` eliminado de estas dos vistas (no del modificador en sí — puede seguir existiendo).
- [ ] Build limpio en iPhone 15 Pro y iPad simulator.
- [ ] Dark Mode: verificar que `Theme.surface` y cards se ven bien. Si no, envolver con `Color(.systemBackground)` y dejar para iteración.

---

## 7 · Referencia visual

El mockup de referencia está en `Insacol App Redesign.html` (dirección B). Tomar como guía visual exacta. Si hay duda sobre spacing/colores, copiar del mockup.

Cualquier ambigüedad → preguntar antes de inventar.
