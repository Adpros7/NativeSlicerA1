import SwiftUI

/// Device workflow: real SSDP discovery, LAN MQTT connect, parsed
/// status, FTPS upload, and starting a new print — every control here
/// calls a real `DeviceSessionModel`/`ProjectDocument` method, nothing
/// decorative. "Start a New Print" (P8) exports a real Bambu-compatible
/// project 3MF with G-code embedded at `Metadata/plate_1.gcode`
/// (`ProjectDocument.exportProjectThreeMF`, the vendored `Format/
/// bbs_3mf.cpp` writer BambuStudio's own "send to printer" flow uses —
/// previously unported, see ARCHITECTURE.md's "two 3MF formats" note),
/// uploads it, then issues the real `project_file` MQTT command. Pause/
/// resume/stop/upload-plain-G-code continue to work independently
/// against whatever the printer is already running.
struct DeviceView: View {
    @ObservedObject var document: ProjectDocument
    @StateObject private var session = DeviceSessionModel()
    @State private var useAMS = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Device").font(.headline)

            GroupBox("Discovery") {
                VStack(alignment: .leading, spacing: 6) {
                    if session.discovered.isEmpty {
                        Text("Listening for Bambu A1 printers on the LAN (SSDP, UDP 1990/2021)…")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(session.discovered, id: \.serial) { printer in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(printer.model ?? "Bambu A1").bold()
                                    Text("\(printer.ipAddress) • \(printer.serial)").font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(session.connectedSerial == printer.serial && session.isConnected ? "Connected" : "Connect") {
                                    session.connect(to: printer)
                                }
                                .disabled(session.connectedSerial == printer.serial && session.isConnected)
                            }
                        }
                    }
                    SecureField("LAN access code", text: $session.accessCode)
                }
            }

            if session.isConnected {
                GroupBox("Status") {
                    if let status = session.lastStatus {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("State: \(status.rawGCodeState ?? "unknown")")
                            if let percent = status.percentComplete { Text("Progress: \(percent)%") }
                            if let layer = status.currentLayer, let total = status.totalLayers { Text("Layer \(layer)/\(total)") }
                            if let nozzle = status.nozzleTemperature { Text("Nozzle: \(nozzle, specifier: "%.1f")°C") }
                            if let bed = status.bedTemperature { Text("Bed: \(bed, specifier: "%.1f")°C") }
                        }
                        .monospacedDigit()
                    } else {
                        Text("Connected — waiting for the first status report…").foregroundColor(.secondary)
                    }
                }

                GroupBox("Camera") {
                    VStack(alignment: .leading, spacing: 6) {
                        if let frame = session.lastCameraFrame, let image = NSImage(data: frame) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 320)
                        } else {
                            Text("No snapshot yet.").foregroundColor(.secondary)
                        }
                        Button(session.isFetchingCamera ? "Fetching…" : "Fetch Snapshot") {
                            Task { await session.fetchCameraFrame() }
                        }
                        .disabled(session.isFetchingCamera)
                        Text("1 fps hardware limit — on-demand snapshot, not a live stream.")
                            .font(.caption).foregroundColor(.secondary)
                    }
                }

                GroupBox("Failure Monitoring") {
                    Toggle("Automatically pause on detected failure", isOn: $session.autoInterventionEnabled)
                    Text("A local notification always posts on a detected failure (gcode_state FAILED or a nonzero print_error); this additionally calls Pause.")
                        .font(.caption).foregroundColor(.secondary)
                }

                GroupBox("Print Controls") {
                    HStack {
                        Button("Pause", action: session.pausePrint)
                        Button("Resume", action: session.resumePrint)
                        Button("Stop", role: .destructive, action: session.stopPrint)
                        Spacer()
                        Button("Disconnect", action: session.disconnect)
                    }
                }

                GroupBox("Upload") {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(session.isUploading ? "Uploading…" : "Upload Sliced G-code") {
                            guard let path = document.lastGCodePath else { return }
                            Task { await session.uploadGCode(localPath: path) }
                        }
                        .disabled(document.lastGCodePath == nil || session.isUploading)
                        if document.lastGCodePath == nil {
                            Text("Slice the plate first.").font(.caption).foregroundColor(.secondary)
                        }
                        if let remotePath = session.lastUploadedRemotePath {
                            Text("Uploaded to \(remotePath)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                GroupBox("Start a New Print") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Use AMS Lite", isOn: $useAMS)
                        Button(session.isUploading ? "Starting…" : "Export, Upload & Start Print") {
                            startNewPrint()
                        }
                        .disabled(document.objectsOnActivePlate.isEmpty || session.isUploading)
                        if document.objectsOnActivePlate.isEmpty {
                            Text("Place at least one object on the active plate first.")
                                .font(.caption).foregroundColor(.secondary)
                        } else {
                            Text("Slices the active plate, embeds the G-code into a real project 3MF, uploads it, then starts printing.")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }

            if let error = session.lastDeviceError {
                Text(error).foregroundColor(.red).font(.caption)
            }

            Spacer()
        }
        .padding()
        .task { session.startDiscovery() }
    }

    /// Exports the active plate as a real project 3MF to a temp file
    /// (`ProjectDocument.exportProjectThreeMF`), then hands it to
    /// `DeviceSessionModel.startPrint(projectThreeMFAt:useAMS:)` for the
    /// upload + `project_file` MQTT command.
    private func startNewPrint() {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).3mf")
        do {
            try document.exportProjectThreeMF(to: tempURL)
        } catch {
            session.lastDeviceError = "Export failed: \(error.localizedDescription)"
            return
        }
        Task {
            await session.startPrint(projectThreeMFAt: tempURL.path, useAMS: useAMS)
            try? FileManager.default.removeItem(at: tempURL)
        }
    }
}
