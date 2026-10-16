import SwiftUI

/// P4-009: assembly/plate preview. Upstream's `GUI/Plater.cpp` renders a
/// full 3D thumbnail per plate; this is a 2D top-down schematic built
/// from each object's REAL world-space XY footprint
/// (`ProjectDocument.platePreview`, same `worldBoundingBox` the P4-006
/// cut plane already uses) — a real "what's on this plate, does it fit"
/// view, not a placeholder graphic. A plate switcher sits alongside it
/// so this doubles as the batch-job (P4-008) plate picker.
struct PlatePreviewView: View {
    @ObservedObject var document: ProjectDocument
    let bedWidth: Float = 256
    let bedHeight: Float = 256

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Plate", selection: $document.activePlateID) {
                ForEach(document.plates) { plate in
                    Text(plate.name).tag(plate.id)
                }
            }
            .labelsHidden()

            HStack {
                Button("Add Plate") { document.addPlate() }
                Button("Remove Plate", role: .destructive) { document.removePlate(document.activePlateID) }
                    .disabled(document.plates.count <= 1)
            }

            GeometryReader { proxy in
                let scale = min(proxy.size.width / CGFloat(bedWidth), proxy.size.height / CGFloat(bedHeight))
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(Color.secondary, lineWidth: 1)
                        .frame(width: CGFloat(bedWidth) * scale, height: CGFloat(bedHeight) * scale)

                    ForEach(document.platePreview(bedWidth: bedWidth, bedHeight: bedHeight), id: \.objectID) { entry in
                        let x = CGFloat(entry.minX) * scale
                        // Bed Y grows "up" (away from origin); SwiftUI Y
                        // grows down, so flip for a top-down view.
                        let bedTopY = CGFloat(bedHeight) * scale
                        let rectHeight = CGFloat(entry.maxY - entry.minY) * scale
                        let y = bedTopY - CGFloat(entry.maxY) * scale
                        Rectangle()
                            .fill(entry.withinBed ? Color.accentColor.opacity(0.35) : Color.red.opacity(0.35))
                            .overlay(Rectangle().stroke(entry.withinBed ? Color.accentColor : Color.red, lineWidth: 1))
                            .frame(width: CGFloat(entry.maxX - entry.minX) * scale, height: rectHeight)
                            .offset(x: x, y: y)
                    }
                }
            }
            .frame(minHeight: 160)

            Text("\(document.objectsOnActivePlate.count) object(s) on \(document.plates.first(where: { $0.id == document.activePlateID })?.name ?? "plate")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 280, minHeight: 260)
    }
}
