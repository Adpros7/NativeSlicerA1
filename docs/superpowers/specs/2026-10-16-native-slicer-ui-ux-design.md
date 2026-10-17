# NativeSlicerA1 UI/UX Design

**Intent:** Replace the blank-start viewport with a usable native macOS slicer shell. The product is a focused A1 workflow: prepare a plate, inspect a real slice, then deliver it to a connected printer. Usability and truthful controls outrank decorative imitation of Bambu Studio or OrcaSlicer.

## Design direction

**Quiet industrial drafting surface.** Use macOS `NavigationSplitView`, `Toolbar`, `Inspector`, `GroupBox`, system typography, semantic colors, SF Symbols, and standard control sizing. The viewport remains the visual focus; controls are compact, labeled, keyboard-accessible, and dark-mode native. No custom web aesthetic, faux 3D controls, hidden critical action, or decorative nonfunctional panel.

## Required workflows

### Prepare

- The viewport *always* renders the 256 × 256 mm A1 plate: translucent plate mesh, 10 mm grid, X/Y/Z axes, front-origin marker, and visible `256 × 256 × 256 mm` dimension labels. It must render before models load.
- Sidebar sections: **Printer** (A1 + nozzle profile), **Filament** (selected compatible profile), **Process** (layer height/infill/support summary and Settings action), and **Objects** (named/numbered selection, count, import empty state).
- Toolbar: Import, Arrange (calls `autoArrangeActivePlate`), Slice, and contextual delete/model editing actions. Disabled actions explain why through nearby empty/disabled-state text, not silent emptiness.
- Empty state overlays the plate without replacing it: “Start a plate” and actions Import Model / Browse MyMiniFactory. Drag-and-drop remains functional.

### Preview

- Available after a real toolpath exists. Shows toolpath viewport, layer/time/statistics summary, feature/tool color mode, and export G-code action.
- Preview never claims estimated values without actual `EstimatedPrintStatistics`; it displays genuine duration, filament, purge, and tool-change data once Phase 6 reporting is connected.

### Device

- Shows discovery/connection status and selected printer. G-code upload/print controls are enabled only when a real connection and an exported/sliced artifact exist; disconnected state presents connect/discover actions, not fake telemetry.
- Print, pause, resume, and stop map only to implemented printer controls. Until each capability lands, it is visibly unavailable with an exact reason.

## Layout and responsive rules

- Top-level segmented workflow picker: Prepare / Preview / Device.
- Minimum usable width 860 pt: collapsible 260 pt sidebar, viewport center, optional 280 pt inspector on wide windows.
- Compact width: sidebar uses a toggle; critical Import/Slice remain in the toolbar; settings move to a sheet.
- Standard and wide sizes must be screenshot-verified in light and dark appearance.

## Functional contract

Every visible action routes to an existing `ProjectDocument`, slicing, export, repository, or printer operation. A control with no reachable implementation is absent; an unavailable real operation is represented as disabled with its precondition stated. UI state derives from document state — no duplicate fake profile/object/print state.

## Verification

- Unit tests cover workflow availability rules, empty-state conditions, and A1 plate/grid geometry generation.
- UI regression proof captures empty, populated-Prepare, Preview, and disconnected-Device surfaces at compact, standard, and wide window widths.
- Run full suite after each UI milestone; preserve existing import, arrange, slice, export, and toolpath tests.
