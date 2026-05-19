import Foundation
import Observation

/// Caché en memoria para marcas, tipos, capacidades y extintores de catálogo.
/// Una sola carga compartida por la sesión.
@MainActor
@Observable
final class CatalogCache {
    static let shared = CatalogCache()

    private(set) var extintores: [ExtintorDto] = []
    private(set) var marcas: [Int64: String] = [:]
    private(set) var tipos: [Int64: String] = [:]
    private(set) var capacidades: [Int64: String] = [:]

    private var isLoaded = false
    private var loadingTask: Task<Void, Never>?

    private init() {}

    /// Carga el catálogo una sola vez. Si ya está cargando, espera la misma task.
    func loadIfNeeded() async {
        if isLoaded { return }
        if let t = loadingTask { await t.value; return }
        let task = Task { await self.loadAll() }
        loadingTask = task
        await task.value
        loadingTask = nil
    }

    private func loadAll() async {
        do {
            async let exts = APIClient.shared.listExtintoresCatalogo()
            async let mar = APIClient.shared.listMarcasExtintor()
            async let tip = APIClient.shared.listTiposExtintor()
            async let cap = APIClient.shared.listCapacidadesExtintor()
            let (e, m, t, c) = try await (exts, mar, tip, cap)
            self.extintores = e
            self.marcas = Dictionary(uniqueKeysWithValues: m.compactMap { dto in
                guard let id = dto.id else { return nil }
                return (id, dto.nombre ?? "—")
            })
            self.tipos = Dictionary(uniqueKeysWithValues: t.compactMap { dto in
                guard let id = dto.id else { return nil }
                return (id, dto.nombre ?? "—")
            })
            self.capacidades = Dictionary(uniqueKeysWithValues: c.compactMap { dto in
                guard let id = dto.id else { return nil }
                return (id, dto.displayText)
            })
            self.isLoaded = true
        } catch {
            // Si falla, permitimos reintentar la próxima vez.
            self.isLoaded = false
        }
    }

    /// "Marca Tipo Capacidad" para un extintor del catálogo.
    func displayName(for extintorCatalogoId: Int64?) -> String {
        guard let id = extintorCatalogoId,
              let ext = extintores.first(where: { $0.id == id })
        else { return "Extintor" }
        return displayName(for: ext)
    }

    func displayName(for ext: ExtintorDto) -> String {
        let m = ext.marcaId.flatMap { marcas[$0] } ?? ""
        let t = ext.tipoId.flatMap { tipos[$0] } ?? ""
        let c = ext.capacidadId.flatMap { capacidades[$0] } ?? ""
        let parts = [m, t, c].filter { !$0.isEmpty }
        return parts.isEmpty ? "Extintor" : parts.joined(separator: " ")
    }
}
