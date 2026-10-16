import Foundation
import CSlic3rBridge

/// Mirrors upstream `CutConnectorType` (Model.hpp) numeric order exactly —
/// raw values are passed straight across the C-ABI to
/// `nsa1_make_connector_mesh` (P4-005).
enum ConnectorType: Int32, CaseIterable, Sendable {
    case plug = 0
    case dowel = 1
    case snap = 2
    case thread = 3
}

/// Mirrors upstream `CutConnectorStyle`. Snap and Thread connectors ignore
/// this (upstream always treats them as their own fixed shape), matching
/// `ModelObject::get_connector_mesh`'s dispatch order.
enum ConnectorStyle: Int32, CaseIterable, Sendable {
    case prizm = 0
    case frustum = 1
}

/// Mirrors upstream `CutConnectorShape`. Snap and Thread connectors ignore
/// this too (upstream only uses it to pick `its_make_cylinder`'s sector
/// count for Plug/Dowel).
enum ConnectorShape: Int32, CaseIterable, Sendable {
    case triangle = 0
    case square = 1
    case hexagon = 2
    case circle = 3
}

/// A fully-specified connector preset (P4-005): the 4 `CutConnectorType`
/// mesh generators the real engine exposes, with real tolerance parameters
/// matching upstream's `CutConnector`/`apply_tolerance` (CutUtils.cpp).
struct ConnectorPreset: Equatable, Sendable {
    var type: ConnectorType
    var style: ConnectorStyle
    var shape: ConnectorShape
    /// Peg/hole radius in mm.
    var radius: Float
    /// Peg/hole height in mm.
    var height: Float
    /// Additive XY widening applied to the hole side only (0...1 fraction
    /// of radius, matching upstream's `CutConnector::radius_tolerance`).
    var radiusTolerance: Float
    /// Additive Z deepening applied to the hole side only (matches
    /// upstream's `CutConnector::height_tolerance`).
    var heightTolerance: Float

    init(
        type: ConnectorType = .plug,
        style: ConnectorStyle = .prizm,
        shape: ConnectorShape = .circle,
        radius: Float = 5,
        height: Float = 10,
        radiusTolerance: Float = 0,
        heightTolerance: Float = 0.1
    ) {
        self.type = type
        self.style = style
        self.shape = shape
        self.radius = radius
        self.height = height
        self.radiusTolerance = radiusTolerance
        self.heightTolerance = heightTolerance
    }
}

enum ConnectorMeshGenerator {
    /// Generates the real connector solid via upstream
    /// `ModelObject::get_connector_mesh`, scaled exactly as the engine's
    /// own `apply_cut_connectors`/`apply_tolerance` scale it (P4-005).
    /// `forHole: true` produces the wider/deeper cutout volume the engine
    /// uses for the negative-volume side of a connector pair; `false`
    /// produces the exact peg/plug dimensions.
    static func generate(_ preset: ConnectorPreset, forHole: Bool) throws -> LoadedMesh {
        guard let raw = nsa1_make_connector_mesh(
            preset.type.rawValue,
            preset.style.rawValue,
            preset.shape.rawValue,
            preset.radius,
            preset.height,
            preset.radiusTolerance,
            preset.heightTolerance,
            forHole ? 1 : 0
        ) else {
            throw SlicingEngineError.sliceFailed("invalid connector preset")
        }
        return convertConnectorMesh(raw)
    }
}

private func convertConnectorMesh(_ raw: UnsafeMutablePointer<NSA1Mesh>) -> LoadedMesh {
    defer { nsa1_free_mesh(raw) }
    let vertexFloatCount = raw.pointee.vertex_count * 3
    let vertices = Array(UnsafeBufferPointer(start: raw.pointee.vertices, count: vertexFloatCount))
    let indices = Array(UnsafeBufferPointer(start: raw.pointee.indices, count: raw.pointee.index_count))
    return LoadedMesh(vertices: vertices, indices: indices)
}
