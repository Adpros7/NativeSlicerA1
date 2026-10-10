# P0-011: Feature Parity Matrix (Draft)

This document maps features from SPEC.md against BambuStudio, OrcaSlicer, and this project's planned implementation phases from TODO.md. Status abbreviations:

- **✓** = Implemented and functional
- **◐** = Partially implemented (functional but with limitations)
- **✗** = Not implemented or not applicable
- **N/A** = Not applicable to this printer/project

## 1. CORE SLICING FEATURES

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Layer height setting | ✓ | ✓ | P1-008 | Both support variable layer height |
| Wall/perimeter count | ✓ | ✓ | P1-008 | Core libslic3r feature |
| Infill pattern selection | ✓ | ✓ | P1-008 | Grid, honeycomb, gyroid, etc. |
| Infill density control | ✓ | ✓ | P1-008 | 0-100% supported |
| Support generation | ✓ | ✓ | P1-008 | Tree & linear supports via libslic3r |
| Support type selection | ✓ | ✓ | P1-008 | Tree, linear, grid in Orca; tree in Bambu |
| Support threshold angle | ✓ | ✓ | P1-008 | Configurable overhang threshold |
| Support density | ✓ | ✓ | P1-008 | Per-area support pattern |
| Raft generation | ✓ | ✓ | P1-008 | Standard raft types |
| Top/bottom shell thickness | ✓ | ✓ | P1-008 | Solid layers configuration |
| Seam position control | ✓ | ✓ | P1-008 | Random, nearest, aligned options |
| Ironing (top surface) | ✓ | ✓ | P1-008 | Arachne wall generator |
| Brim/skirt generation | ✓ | ✓ | P1-008 | Brim, purge, wipe tower variants |

## 2. MODEL IMPORT/EXPORT

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| STL import | ✓ | ✓ | P1-004 | Standard binary & ASCII STL |
| OBJ import | ✓ | ✓ | P1-004 | Wavefront OBJ format |
| 3MF import | ✓ | ✓ | P1-005 | Includes textures, models, metadata |
| STEP import | ◐ | ✓ | P1-004 | Bambu: via webview; Orca: native via libslic3r |
| Other CAD formats | ◐ | ✓ | P1-004 | Orca supports via AssimpImport; Bambu limited |
| STL export | ✓ | ✓ | P1-009 | Binary STL output |
| OBJ export | ✓ | ✓ | P1-009 | Wavefront OBJ output |
| 3MF export | ✓ | ✓ | P1-009 | Full project preservation |
| Model preview/visualization | ✓ | ✓ | P1-004 | Real-time 3D viewport |
| Unit detection | ◐ | ◐ | P4-001 | Both warn on unusual sizes; neither auto-converts |
| Drag-and-drop import | ✓ | ✓ | P1-004 | Standard UI gesture |

## 3. OBJECT TRANSFORMATIONS

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Move/translate | ✓ | ✓ | P1-006 | XYZ positioning |
| Rotate (free) | ✓ | ✓ | P1-006 | Arbitrary axis rotation |
| Rotate (axis-aligned) | ✓ | ✓ | P1-006 | 90° increments |
| Scale | ✓ | ✓ | P1-006 | Uniform & non-uniform scaling |
| Mirror/flip | ✓ | ✓ | P1-006 | XYZ axis mirroring |
| Auto-orient | ✓ | ✓ | P1-006 | Automatic print orientation |
| Variable layer height | ✓ | ✓ | P4-001 | Per-region height optimization |

## 4. PAINTING FEATURES (Multicolor)

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Multicolor painting (flat) | ✓ | ✓ | P3-004 | Paint faces with colors |
| Multicolor painting (brush/sphere) | ✓ | ✓ | P3-004 | Freehand painting tool |
| Color fill tool | ✓ | ✓ | P3-004 | Flood-fill for connected faces |
| Texture-to-color auto painting | ✓ | ✗ | P3-004 | Bambu 2.7+ feature; Orca lacks this |
| Color mixing (multi-filament blends) | ✓ | ✗ | P3-004 | Bambu 2.5.3+; requires CMYK kit |
| Gradient effects | ✓ | ◐ | P3-004 | Bambu supports; Orca limited |
| Paint preservation after cut | ✓ | ◐ | P3-004 | Bambu 2.7+; Orca has issues (Issue #7565) |

## 5. PAINTING FEATURES (Support & Seam)

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Support painting (enforce) | ✓ | ✓ | P3-005 | Force supports on painted areas |
| Support painting (block) | ✓ | ✓ | P3-005 | Block supports on painted areas |
| Seam painting | ◐ | ◐ | P3-005 | Both have seam control; not dedicated paint tool |

## 6. CONNECTOR SYSTEM

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Connector types (basic) | ◐ | ◐ | P4-005,P4-006 | Only Plug, Dowel, Snap in both |
| Cylindrical pin connectors | ◐ | ◐ | P4-005,P4-006 | Via Dowel type; limited customization |
| Snap-fit connectors | ◐ | ◐ | P4-005,P4-006 | Via Snap type; design limitations |
| Dovetail connectors | ✗ | ✗ | P4-005,P4-006 | **Gap: Neither upstream supports this** |
| Rectangular pin connectors | ✗ | ✗ | P4-005,P4-006 | **Gap: Neither upstream supports this** |
| Peg-and-hole joints | ◐ | ◐ | P4-005,P4-006 | Partial via Plug; limited customization |
| Puzzle joints | ✗ | ✗ | P4-005,P4-006 | **Gap: Neither upstream supports this** |
| Threaded connectors | ✗ | ✗ | P4-005,P4-006 | **Gap: Neither upstream supports this** |
| Screw-compatible joints | ✗ | ✗ | P4-005,P4-006 | **Gap: Neither upstream supports this** |
| Magnet pocket support | ✗ | ✗ | P4-005,P4-006 | **Gap: Neither upstream supports this** |
| Custom connector editing | ◐ | ◐ | P4-006 | Size/depth/tolerance; not arbitrary geometry |
| Connector preset management | ◐ | ◐ | P4-005 | Basic presets; no extensible system |
| Connector reversibility | ✗ | ◐ | P4-007 | Bambu has issue #7565 (connectors not splitting); Orca partial |
| Known connector issues | Bug #7565 | Issue #7565 | P4-007 | Both have connector-splitting bugs |

**Gap Summary for Connectors:** Neither upstream project has a comprehensive connector system. Both have basic alignment-only connectors (Bambu: Plug/Dowel/Snap; Orca: cylindrical dowels). SPEC requires 8+ connector types with full customization—this is a major new implementation area.

## 7. MODEL SPLITTING & OVERSIZING

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Automatic oversized detection | ◐ | ◐ | P4-001 | Both warn if model exceeds bed; not auto-split |
| Automatic model splitting | ✗ | ✗ | P4-004 | **Gap: Neither upstream has this** |
| Manual plane-based splitting | ✓ | ✓ | P4-004 | Cut tool with single plane |
| Split plane visualization | ✓ | ✓ | P4-004 | Visual preview of cuts |
| Multi-plane splitting | ✗ | ✗ | P4-004 | **Gap: Neither upstream supports this** |
| Manual split control | ✓ | ✓ | P4-004 | Adjust cut planes |
| Splitting reversibility | ✗ | ◐ | P4-004 | Bambu/Orca: splitting is destructive |

**Gap Summary for Splitting:** Neither upstream project has automatic intelligent splitting for oversized models. The cut tool is manual, single-plane, and destructive. SPEC requires automatic multi-plane splitting with reversible transformations—this is a major new feature.

## 8. MULTI-PLATE MANAGEMENT

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Multiple plates support | ✓ | ✓ | P1-007 | Up to 10 plates in Bambu/Orca |
| Manual plate assignment | ✓ | ✓ | P1-007 | Drag/drop objects to plates |
| Per-plate slicing | ✓ | ✓ | P1-008 | Each plate generates G-code |
| Automatic arrangement | ◐ | ◐ | P4-008 | Basic auto-arrange; not intelligent |
| Intelligent multi-plate arrangement | ✗ | ✗ | P4-008 | **Gap: Neither optimizes across plates** |
| Assembly preview | ◐ | ◐ | P4-009 | Visualization; not assembly instructions |
| Per-plate cost estimation | ◐ | ◐ | P1-008 | Basic; not per-plate |

**Gap Summary:** Neither upstream project has intelligent multi-plate arrangement that optimizes for color grouping, material usage, or print duration across plates. SPEC requires automatic distribution with optimization.

## 9. CALIBRATION FEATURES

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Temperature tower | ✓ | ✓ | P3-002 | Automated G-code generation |
| Flow rate calibration | ◐ | ✓ | P3-002 | Bambu: preset; Orca: automated wizard |
| Pressure advance (K-factor) | ◐ | ✓ | P3-002 | Bambu: limited; Orca: full wizard |
| Retraction test | ✓ | ✓ | P3-002 | String/blob test patterns |
| Bed adhesion test | ✓ | ✓ | P3-002 | First-layer adhesion diagnostics |
| Max volumetric flow test | ✓ | ✓ | P3-002 | Extrusion speed limits |
| Dimensional accuracy test | ✓ | ✓ | P3-002 | Tolerance verification |
| Hole compensation test | ✓ | ✓ | P3-002 | XY compensation |
| Vertical artifacts test | ✓ | ✓ | P3-002 | Layer alignment diagnostics |
| Tolerance test | ✓ | ✓ | P3-002 | Dimensional accuracy |
| Calibration wizard workflow | ◐ | ✓ | P3-002 | Orca has 9 wizards; Bambu has presets |
| Results persistence | ✓ | ✓ | P3-002 | Save to filament profiles |

## 10. FILAMENT MANAGEMENT

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Material profiles (PLA/PLA+/PETG/TPU) | ✓ | ✓ | P2-006 | Bundled presets for common materials |
| Custom material profiles | ✓ | ✓ | P2-006 | User-defined materials |
| Spool inventory | ◐ | ◐ | P2-006 | Bambu via printer; Orca: manual tracking |
| Remaining filament estimation | ◐ | ◐ | P2-006 | Based on weight/length calculations |
| Filament cost tracking | ◐ | ◐ | P2-006 | Per-spool pricing; not fully integrated |
| AMS Lite integration | ✓ | ✓ | P2-006 | Full multi-material workflow |
| RFID filament detection | ✓ | ✗ | P2-006 | Bambu only (native A1 feature) |
| Filament compatibility checking | ◐ | ◐ | P2-006 | Warnings for TPU/adhesion issues |
| Material-aware defaults | ✓ | ✓ | P2-006 | Temperature/speed presets per material |

## 11. PRINTER INTEGRATION (A1 Communication)

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| LAN discovery | ✓ | ✓ | P2-002 | mDNS/UDP broadcast |
| Cloud connectivity | ✓ | ◐ | P2-003 | Bambu official; Orca community reverse-engineered |
| MQTT monitoring | ✓ | ✓ | P2-003 | Real-time printer state |
| Printer status monitoring | ✓ | ✓ | P2-003 | Online/idle/printing states |
| Temperature monitoring | ✓ | ✓ | P2-003 | Nozzle & bed temperatures |
| Current layer tracking | ✓ | ✓ | P2-003 | Layer-by-layer progress |
| Print progress tracking | ✓ | ✓ | P2-003 | Percentage complete |
| Time estimation | ✓ | ✓ | P2-003 | ETA calculation |
| Print upload (via LAN) | ✓ | ✓ | P2-004 | FTP/MQTT file transfer |
| Print upload (via cloud) | ✓ | ◐ | P2-004 | Bambu official; Orca limited |
| Print start control | ✓ | ✓ | P2-005 | Remote start job |
| Pause control | ✓ | ✓ | P2-005 | Remote pause |
| Resume control | ✓ | ✓ | P2-005 | Remote resume |
| Cancel control | ✓ | ✓ | P2-005 | Remote stop job |
| Camera access (A1) | ◐ | ◐ | P7-001 | A1 camera at 1FPS; unreliable; no AI support |

**Gap Summary:** Both upstream projects have solid A1 LAN/cloud integration. The A1's camera is 1FPS and lacks AI support in either, so failure detection is experimental.

## 12. 3D VISUALIZATION

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Model viewport | ✓ | ✓ | P1-002 | Real-time 3D rendering |
| Layer visualization | ✓ | ✓ | P1-009 | Layer-by-layer preview |
| Toolpath preview | ✓ | ✓ | P1-009 | G-code path visualization |
| Support visualization | ✓ | ✓ | P1-009 | Support structure rendering |
| Model preview/cross-section | ✓ | ✓ | P1-002 | Orthographic slicing views |
| Orthographic/perspective views | ✓ | ✓ | P1-002 | Selectable view modes |
| Zoom/pan/rotate | ✓ | ✓ | P1-002 | Standard 3D interaction |
| Lighting controls | ✓ | ✓ | P1-002 | Ambient, directional lighting |
| Material color visualization | ✓ | ✓ | P1-009 | Per-object material preview |
| Filament change visualization | ✓ | ✓ | P1-009 | Color transitions in preview |

## 13. G-CODE FEATURES

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| G-code generation | ✓ | ✓ | P1-008 | Full slicing → G-code pipeline |
| G-code preview/visualization | ✓ | ✓ | P1-009 | Layer-by-layer toolpath preview |
| Layer-by-layer stepping | ✓ | ✓ | P1-009 | Slider to view each layer |
| Filament change markers | ✓ | ✓ | P1-009 | Visual indicators in preview |
| G-code export | ✓ | ✓ | P1-009 | Save .gcode files |
| G-code import | ✓ | ✓ | P1-009 | Load existing G-code for preview |
| G-code to 3MF reconstruction | ✗ | ✗ | P7-007 | **Gap: Neither upstream supports this** |

**Gap Summary:** Neither upstream project can reconstruct STL/3MF from G-code. SPEC section 25 requires approximate geometry recovery from extrusion paths—this is a novel implementation area.

## 14. MESH REPAIR

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Non-manifold detection | ✓ | ✓ | P4-002 | Identify closed/open edges |
| Open boundary detection | ✓ | ✓ | P4-002 | Edges with no adjacent faces |
| Inverted normal detection | ✓ | ✓ | P4-002 | Face orientation diagnostics |
| Duplicate face detection | ✓ | ✓ | P4-002 | Overlapping geometry |
| Self-intersection detection | ✓ | ✓ | P4-002 | Geometry overlap diagnostics |
| Disconnected components | ✓ | ✓ | P4-002 | Separate parts tracking |
| Repair workflow (automated) | ◐ | ◐ | P4-002 | Windows-only via 3D Netfabb API |
| Repair workflow (macOS) | ✗ | ✗ | P4-002 | **Gap: Neither works natively on macOS** |
| Manual repair UI | ✗ | ✗ | P4-002 | **Gap: Need native macOS implementation** |
| Mesh simplification | ✓ | ✓ | P4-002 | Polygon reduction |
| Surface smoothing | ✓ | ✓ | P4-002 | Laplacian smoothing |

**Gap Summary:** Both upstream projects use Windows 3D Netfabb for mesh repair (unavailable on macOS). SPEC section 15 requires explicit user-initiated manual repair with diagnostics—this requires native implementation.

## 15. GEOMETRY TOOLS

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Boolean operations | ✓ | ✓ | P4-002 | Union, difference, intersection |
| Cutting/slicing | ✓ | ✓ | P4-004 | Plane-based cutting via Cut tool |
| Merging | ✓ | ✓ | P4-002 | Combine models |
| Flattening | ✓ | ✓ | P4-002 | Project to plane |
| Measurement | ✓ | ✓ | P4-002 | Ruler/distance tools |
| Alignment | ✓ | ✓ | P4-002 | Snap-to-grid, align features |
| Clearance analysis | ◐ | ◐ | P4-002 | Via toolpath collision checking |
| Hole analysis | ◐ | ◐ | P4-002 | Hole detection via mesh analysis |

## 16. OPTIMIZATION & MULTICOLOR

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Purge volume optimization | ◐ | ✓ | P6-003 | Orca more advanced; Bambu basic |
| Purge tower optimization | ◐ | ✓ | P6-003 | Tower placement & size |
| Color transition analysis | ◐ | ◐ | P6-002 | Both track transitions; limited optimization |
| Flush into infill | ◐ | ◐ | P6-003 | Partial support in both |
| Flush into supports | ◐ | ◐ | P6-003 | Partial support in both |
| Filament change minimization | ◐ | ◐ | P6-001 | Basic optimization |
| Print duration optimization | ◐ | ◐ | P6-001 | Speed/acceleration tweaks |
| Multi-region color scheduling | ✗ | ✗ | P6-004 | **Gap: Neither upstream supports this** |
| Advanced scheduling (experimental) | ✗ | ✗ | P6-004 | **Gap: SPEC section 13.2 novel feature** |
| Optimization report | ◐ | ◐ | P6-006 | Basic stats; not detailed comparison |

**Gap Summary:** Neither upstream has advanced multicolor optimization as specified in SPEC sections 13-14. OrcaSlicer has better basic purge optimization than Bambu, but neither has region-based scheduling, variable-height printing coordination, or detailed optimization reports.

## 17. ADVANCED FEATURES

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Toolpath simulation | ✓ | ✓ | P7-007 | Nozzle path visualization |
| Sequential/object printing | ✓ | ✓ | P3-006,P7-001 | One object at a time |
| Sequential printing validation | ✓ | ✓ | P3-006 | Collision checking |
| Timelapse support | ✓ | ✓ | P3-006 | Snapshot-based video |
| Smooth timelapse | ✓ | ◐ | P3-006 | Bambu: full support; Orca: partial |
| Timelapse disable option | ✓ | ✓ | P3-006 | Turn off timelapse |
| Undo/redo | ✓ | ✓ | P1-006 | Standard edit history |
| Autosave | ✓ | ✓ | P1-007 | Automatic project saving |
| Crash recovery | ✓ | ✓ | P1-007 | Recover unsaved work |
| Cost estimation | ◐ | ◐ | P1-008 | Basic filament & time costs |
| Electricity cost calculation | ✗ | ✗ | P2-005 | **Gap: Neither upstream calculates power** |
| Print history | ✓ | ✓ | P2-005 | Archive completed jobs |
| Print failure detection (visual) | ◐ | ✗ | P7-002 | Bambu X1C only (not A1); Orca none |

**Gap Summary:** A1 lacks visual failure detection in BambuStudio. Neither upstream has power consumption estimation. SPEC section 23 requires local Core ML-based detection—this is novel.

## 18. PROJECT MANAGEMENT

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| 3MF project format | ✓ | ✓ | P1-005,P1-007 | Standard 3MF archive with metadata |
| Project import/export | ✓ | ✓ | P1-007 | Save/load complete projects |
| Project history | ✓ | ✓ | P1-007 | Version tracking |
| Version compatibility | ◐ | ◐ | P1-007 | Read old versions; limited forward compat |
| Settings preservation | ✓ | ✓ | P1-007 | Profiles persist in projects |
| Plate management | ✓ | ✓ | P1-007 | Multiple build plates per project |

## 19. UI/UX FEATURES

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Native UI (platform-specific) | ◐ | ✗ | P1-001 | Bambu: partial wxWidgets; Orca: wxWidgets only |
| Dark/light mode | ✓ | ✓ | P1-001 | Theme support |
| Keyboard shortcuts | ✓ | ✓ | P1-001 | Standard hotkeys |
| Drag-and-drop | ✓ | ✓ | P1-004 | Drop files to import |
| Native file dialogs | ✓ | ✓ | P1-007 | OS file picker |
| Preferences panel | ✓ | ✓ | P1-001 | Settings UI |
| Responsive UI | ✓ | ✓ | P1-001 | Non-blocking operations |
| Accessible controls | ◐ | ◐ | P1-001 | Screen reader support; limited in both |
| Native notifications | ✓ | ✓ | P2-005 | Print state alerts |

## 20. MAKERWORLD INTEGRATION

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| MakerWorld browsing | ✓ | ✗ | P5-002 | Bambu via WebView; Orca none |
| Model search | ✓ | ✗ | P5-002 | Full text search |
| Category browsing | ✓ | ✗ | P5-002 | Curated categories |
| Filtering/sorting | ✓ | ✗ | P5-002 | By rating, downloads, date |
| Model preview | ✓ | ✗ | P5-002 | 3D preview before download |
| Thumbnails | ✓ | ✗ | P5-002 | Quick visual reference |
| Model description | ✓ | ✗ | P5-002 | Text, images, tags |
| Available profiles display | ✓ | ✗ | P5-002 | Show presets bundled with model |
| Model downloading | ✓ | ✗ | P5-002 | Direct download to slicer |
| Direct import to slicer | ✓ | ✗ | P5-002 | Instant import workflow |
| Direct slicing workflow | ✓ | ✗ | P5-002 | Download → slice in one action |
| One-click printing | ✓ | ✗ | P5-002 | Direct to printer (with presets) |
| Attribution/licensing | ✓ | ✗ | P5-002 | Creator credits, CC/commercial flags |

**Gap Summary:** Only BambuStudio has MakerWorld integration via WebView. OrcaSlicer lacks this entirely. SPEC section 6 requires native macOS browser with identical workflows. This will require API reverse-engineering or official partnership.

## 21. ADDITIONAL REPOSITORIES

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Unified model search | ✗ | ✗ | P5-005 | **Gap: Neither has multi-repo search** |
| License filtering | ✗ | ✗ | P5-005 | **Gap: Novel feature** |
| Format filtering | ✗ | ✗ | P5-005 | **Gap: Novel feature** |
| Source attribution | ✓ | ✓ | P5-005 | Creator credits |
| Download management | ✓ | ✓ | P5-005 | Queue, pause, resume |

**Gap Summary:** SPEC section 7 requires extensible repository integration beyond MakerWorld. Neither upstream has this.

## 22. SAFETY & VALIDATION

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Printer limit validation | ✓ | ✓ | P2-007,P4-008 | Build volume, temperature limits |
| Movement boundary checking | ✓ | ✓ | P2-007 | Collision detection |
| Temperature limit validation | ✓ | ✓ | P2-007 | Min/max nozzle & bed temps |
| Extrusion limit validation | ✓ | ✓ | P2-007 | E-motor safety limits |
| Toolhead clearance checking | ✓ | ✓ | P2-007,P3-006 | Hotend/nozzle collision detection |
| Gantry clearance checking | ✓ | ✓ | P2-007,P3-006 | Frame/motion envelope |
| Sequential printing validation | ✓ | ✓ | P3-006 | Multi-object collision checking |
| Filament compatibility | ✓ | ✓ | P2-006 | TPU warnings, incompatibility alerts |
| G-code structure validation | ✓ | ✓ | P1-008,P2-007 | Syntax checking |
| Firmware compatibility | ✓ | ✓ | P2-007 | Version-specific feature gating |
| Print failure prevention | ◐ | ◐ | P7-001 | Floating geometry, weak bed adhesion warnings |

## 23. PERFORMANCE & OPTIMIZATION

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Apple Silicon optimization | N/A | ✗ | P1-001 | Neither is native macOS; this is novel |
| Efficient multithreading | ✓ | ✓ | P1-008 | Parallel slicing |
| Background slicing | ✓ | ✓ | P1-008 | Non-blocking UI |
| Incremental updates | ✓ | ✓ | P1-008 | Partial re-slice on setting change |
| Cached computations | ✓ | ✓ | P1-008 | Mesh caching, profile caching |
| Memory-efficient processing | ✓ | ✓ | P1-008 | Handle large models |
| Large model performance | ✓ | ✓ | P1-008 | 500k+ polygon meshes |

## 24. DETERMINISTIC SLICING

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Reproducible G-code | ✓ | ✓ | P1-008 | Identical settings → identical output |
| Version tracking | ✓ | ✓ | P1-007 | App, engine, profile versions |
| Model hash tracking | ✓ | ✓ | P1-007 | Detect mesh changes |
| Settings snapshots | ✓ | ✓ | P1-007 | Preserve configuration state |

## 25. SECURITY & PRIVACY

| Feature | BambuStudio | OrcaSlicer | NativeSlicerA1 | Notes |
|---------|-------------|-----------|----------------|-------|
| Keychain credential storage | N/A | N/A | P1-001,P5-001 | Neither is macOS native; this is novel |
| No telemetry | ◐ | ✓ | P1-001 | Orca none; Bambu has optional analytics |
| No credential collection | ✓ | ✓ | P1-001 | Both respect local-only auth |
| Secure printer communication | ✓ | ✓ | P2-003 | TLS/MQTT encryption |
| Open source license | ✓ | ✓ | P1-001 | AGPLv3 (see RESEARCH.md P0-004) |

## FEATURE SUMMARY BY CATEGORY

### Complete Parity (Both upstream projects have feature)
- Core slicing (layer height, infill, supports, etc.)
- Model import/export (STL, OBJ, 3MF, STEP via Orca)
- Basic transformations (move, rotate, scale, mirror)
- Basic painting (multicolor, support, seam)
- Calibration (temperature, flow rate, pressure advance)
- Filament management (materials, AMS Lite)
- Printer integration (LAN, cloud, MQTT, control)
- 3D visualization (viewport, layers, toolpath)
- G-code generation and preview
- Mesh diagnostics (detection only; repair Windows-only)
- Geometry tools (boolean, measurement, alignment)
- Basic optimization (purge, tower)
- Timelapse support
- Project management (3MF)
- Safety validation (limits, collisions)

### Partial Parity (One or both upstream have limitations)
- STEP import (Bambu via web; Orca native)
- Unit detection (both warn; neither converts)
- Advanced connectors (Bambu/Orca: 3 types only; limited customization)
- Mesh repair (both Windows-only via 3D Netfabb)
- Calibration wizards (Orca more complete than Bambu)
- Multi-plate arrangement (basic only)
- Smooth timelapse (Bambu complete; Orca limited)
- Cost estimation (basic; no electricity)
- Optimization reporting (basic stats only)
- Camera/AI (X1C only; A1 at 1FPS with no AI)

### Unique Gaps (Neither upstream project has feature)
- **Comprehensive connector system** (8+ types with full customization)
- **Automatic oversized model splitting** (multi-plane, intelligent)
- **Non-destructive transformations** (full reversibility including connectors)
- **Intelligent multi-plate arrangement** (optimization across plates)
- **Advanced multicolor scheduling** (region-based, variable-height coordination)
- **G-code to 3MF reconstruction** (recover geometry from extrusion paths)
- **Native macOS mesh repair** (Netfabb unavailable on macOS)
- **MakerWorld integration** (OrcaSlicer has none; Bambu has WebView)
- **Additional repository integration** (beyond MakerWorld)
- **Electricity cost calculation**
- **Native swiftUI/Metal interface** (both wxWidgets)
- **Apple Silicon optimization** (neither is native macOS)
- **Keychain integration** (platform-specific)
- **Camera-based failure detection** (experimental; A1 camera not suitable)

## NOTES ON IMPLEMENTATION PHASES

From TODO.md:

- **Phase 1 (P1-xxx):** Foundation — app, metal viewport, slicing engine integration, STL/3MF import, transformations, persistence, slicing, G-code viz.
- **Phase 2 (P2-xxx):** Printer Integration — profiles, discovery, LAN, print upload, device monitoring, AMS mapping, validation.
- **Phase 3 (P3-xxx):** Feature Parity — missing features from both upstream, calibration, advanced slicing, painting, project compatibility.
- **Phase 4 (P4-xxx):** Geometry — unit detection, mesh repair, transformations, splitting, connectors, multi-plate.
- **Phase 5 (P5-xxx):** Online Models — authentication, MakerWorld, downloading, direct slicing, other repos.
- **Phase 6 (P6-xxx):** Optimization — benchmarking, color analysis, purge optimization, region scheduling, reports.
- **Phase 7 (P7-xxx):** Intelligence — camera, failure detection, orientation, recommendations, G-code reconstruction.
- **Phase 8 (P8-xxx):** Production — testing, security, performance, hardware validation, release.

## KEY IMPLEMENTATION DECISIONS

1. **Reuse libslic3r:** Both upstream projects use libslic3r (C++) for slicing. This will be wrapped via C API shim for Swift integration per SPEC section 1.1 and ARCHITECTURE.md.

2. **Connector System:** Major new implementation (not in upstream). SPEC section 11 requires 8+ types; upstream has only 3 basic types with bugs (Issue #7565).

3. **Model Splitting:** New implementation. Upstream cut tool is manual, single-plane, destructive. SPEC requires automatic, multi-plane, reversible.

4. **Multicolor Optimization:** Advanced features beyond both upstream projects. SPEC sections 13-14 require region-based scheduling and detailed reporting.

5. **Native macOS UI:** Neither upstream is native macOS. This project will use SwiftUI + Metal per SPEC section 4.

6. **MakerWorld Integration:** Only BambuStudio has this (WebView). OrcaSlicer has none. SPEC requires native macOS browser integration.

7. **Mesh Repair:** Both upstream use Windows-only 3D Netfabb. SPEC section 15 requires native macOS implementation.

8. **G-code Reconstruction:** Novel feature not in either upstream. SPEC section 25 requires geometry recovery from extrusion paths.

## REFERENCES

- **BambuStudio Source:** `.research/BambuStudio/` — libslic3r at `src/libslic3r/`, UI at `src/slic3r/GUI/`, communication at `src/slic3r/Utils/`
- **OrcaSlicer Source:** `.research/OrcaSlicer/` — same structure; additional calibration code in `src/libslic3r/Calib.*`
- **Both Projects:** Licensed AGPLv3 (see RESEARCH.md P0-004)
- **Bundled Dependencies:** admesh, clipper/clipper2, earcut, qhull, libigl, libnest2d, Arachne, eigen, nlohmann-json, mcut, tinybvh — all MIT/BSD/BSL licensed and reusable
