import SwiftUI

/// Phase 6.5 Device workflow: real SSDP discovery, LAN MQTT connect,
/// parsed status, and FTPS upload — every control here calls a real
/// `DeviceSessionModel` method, nothing decorative. "Start a new print"
/// is intentionally absent: the printer's `project_file` command only
/// accepts a `.3mf` with G-code embedded in `Metadata/plate_1.gcode`
/// (BambuStudio's separate project-3mf format, `Format/bbs_3mf.cpp`,
/// not ported here — see ARCHITECTURE.md's "two 3MF formats" note), so
/// a "start" button would have nothing real to trigger. Upload, status,
/// and pause/resume/stop (which control whatever the printer is already
/// running) all work against the already-sliced plain `.gcode`.
struct DeviceView: View {
    @ObservedObject var document: ProjectDocument
    @StateObject private var session = DeviceSessionModel()

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
            }

            if let error = session.lastDeviceError {
                Text(error).foregroundColor(.red).font(.caption)
            }

            Spacer()
        }
        .padding()
        .task { session.startDiscovery() }
    }
}
