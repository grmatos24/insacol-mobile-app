# Diseño Visual iOS — Insacol App

**Fecha:** 2026-05-20  
**Estado:** Pendiente de implementar

---

## Paleta de marca (extraída de insacol.com)

| Variable | Hex | Descripción |
|----------|-----|-------------|
| `--primary-color` | `#FFC107` | Amber 500 — "Industrial Safety Yellow" |
| `--primary-dark` | `#F59E0B` | Amber oscuro (hover/pressed) |
| `--primary-light` | `#FEF3C7` | Amber muy claro (fondos sutiles) |
| `--secondary-color` | `#0F172A` | Slate 900 — fondo oscuro principal |
| `--accent-color` | `#E2E8F0` | Slate 200 |
| `--text-color` | `#334155` | Slate 700 |
| `--text-light` | `#64748B` | Slate 500 |

---

## Opciones de diseño

### Opción A — Amber Accent (mínimo esfuerzo)

**Qué cambia:** Solo el AccentColor en `Assets.xcassets` → `#FFC107`.

El tab bar y la navigation bar con Liquid Glass de iOS 26 heredan el acento automáticamente. Sin re-diseño de ninguna vista.

**Archivos:** 1
- `insacol-app/Assets.xcassets/AccentColor.colorset/Contents.json` — cambiar a `#FFC107`

**Esfuerzo:** ~5 minutos

---

### Opción B — Glass + Amber ⭐ (recomendada)

**Qué cambia:**
1. **AccentColor** → `#FFC107`
2. **LoginView** — fondo `#0F172A` (navy), campos con `.ultraThinMaterial` glass, botón amber con gradiente `#FFC107 → #F59E0B`
3. **Listas** (Facturas, Cotizaciones, Gastos, Mantenimiento) — filas como glass cards con `.ultraThinMaterial` sobre fondo oscuro
4. **Badges de estado** — amber=pendiente/borrador, verde=pagado/emitido/activo, azul=emitido FE
5. **Montos** — fuente más grande, color `#FFC107`

**Archivos estimados:** 6–8
- `Assets.xcassets/AccentColor.colorset/Contents.json`
- `LoginView.swift`
- `FacturasListView.swift`
- `CotizacionesListView.swift`
- `GastosListView.swift`
- `ReportesMantenimientoListView.swift`
- Posiblemente un `Theme.swift` con constantes de color compartidas

**Implementación técnica (SwiftUI):**
```swift
// Glass card row
.background(.ultraThinMaterial)
.clipShape(RoundedRectangle(cornerRadius: 14))

// Botón amber login
.background(
    LinearGradient(colors: [Color(hex: "#FFC107"), Color(hex: "#F59E0B")],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
)

// Fondo login
.background(Color(hex: "#0F172A").ignoresSafeArea())
```

**Esfuerzo:** ~3–4 horas

---

### Opción C — Navy + Floating Glass (premium)

**Qué cambia (todo lo de B, más):**
1. **Fondo app** — `#0F172A` en lugar de `.systemBackground`
2. **Login** — glow radial amber detrás del logo, logo con borde glass amber
3. **Tarjetas flotantes** — borde izquierdo 2px por estado: amber=pendiente, verde=pagado, azul=emitido
4. **Header de listas** — título grande + chips de filtro inline (reemplaza el `Picker` segmentado)
5. **Tab bar border** — `0.5px solid rgba(255,193,7,0.2)` en lugar del separador gris

**Archivos estimados:** 12–15 (todas las vistas de lista + formularios + theme)

**Esfuerzo:** ~1 día

---

## Sistema de badges de estado (aplica a B y C)

| Estado | Color | SwiftUI |
|--------|-------|---------|
| Pendiente / Borrador | `#FFC107` amber | `.foregroundStyle(.yellow)` con bg `rgba(255,193,7,0.15)` |
| Pagado / Emitido / Activo | `#32D74B` verde | `.foregroundStyle(.green)` con bg |
| Emitido FE | `#0A84FF` azul | `.foregroundStyle(.blue)` con bg |
| Anulado | `#FF453A` rojo | `.foregroundStyle(.red)` con bg |
| Facturada | `#64748B` gris | `.foregroundStyle(.secondary)` |

---

## Notas de implementación

- iOS 26 Liquid Glass se activa solo en tab bar y navigation bar — no requiere código extra, solo el acento correcto.
- Para glass cards: `.background(.ultraThinMaterial)` + `.clipShape(.rect(cornerRadius: 14))` es suficiente en iOS 17+.
- El color hex en SwiftUI se logra con una extensión `Color(hex:)` si no existe ya en el proyecto.
- Mantener soporte de dark/light mode: usar colores semánticos de iOS para texto, solo el acento y fondos especiales en hex fijo.
- La opción B no rompe el light mode — `.ultraThinMaterial` adapta solo.

---

## Decisión pendiente

El usuario debe elegir entre A, B o C antes de crear el plan de implementación.  
Mockup visual guardado en: `.superpowers/brainstorm/86889-1779306163/content/diseno-opciones.html`
