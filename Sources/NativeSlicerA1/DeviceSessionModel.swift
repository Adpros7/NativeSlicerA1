import Foundation
import UserNotifications

/// Drives the Device workflow's real backing state: SSDP discovery
/// (`PrinterDiscovery`), the LAN MQTT connection (`PrinterConnection`),
/// parsed status (`PrintStatusReport`), FTPS upload (`FTPSUploader`),
/// chamber camera snapshots (`CameraStreamClient`, P7-001), and
/// failure-notification/auto-pause (P7-002/P7-003/P7-004). Every
/// published value here comes from an actual network event, never a
/// placeholder default meant to look populated.
@MainActor
final class DeviceSessionModel: ObservableObject {
    @Published private(set) var discovered: [DiscoveredPrinter] = []
    @Published var accessCode: String = ""
    @Published private(set) var connectedSerial: String?
    @Published private(set) var isConnected = false
    @Published private(set) var lastStatus: PrintStatusReport?
    @Published var lastDeviceError: String?
    @Published private(set) var isUploading = false
    @Published private(set) var lastUploadedRemotePath: String?
    @Published private(set) var lastCameraFrame: Data?
    @Published private(set) var isFetchingCamera = false
    /// P7-004: when enabled, a detected real failure (`gcode_state ==
    /// FAILED` or a nonzero `print_error`) automatically calls
    /// `pausePrint()` — off by default; no automatic action without
    /// explicit user opt-in.
    @Published var autoInterventionEnabled = false
    private var discovery: PrinterDiscovery?
    private var connection: PrinterConnection?
    private var connectedHost: String?
    /// Tracks which failure we've already notified/intervened on so a
    /// repeated report with the same `gcode_state`/`print_error` doesn't
    /// re-fire (the printer re-sends its full status periodically).
    private var lastHandledFailureKey: String?

    /// Starts the real SSDP listener (idempotent — a second call is a
    /// no-op while one is already running).
    func startDiscovery() {
        guard discovery == nil else { return }
        let listener = PrinterDiscovery()
        listener.onDiscover = { [weak self] printer in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let index = self.discovered.firstIndex(where: { $0.serial == printer.serial }) {
                    self.discovered[index] = printer
                } else {
                    self.discovered.append(printer)
                }
            }
        }
        do {
            try listener.start()
            discovery = listener
        } catch {
            lastDeviceError = "Discovery failed: \(error.localizedDescription)"
        }
    }

    func connect(to printer: DiscoveredPrinter) {
        connection?.disconnect()
        let conn = PrinterConnection(host: printer.ipAddress, serial: printer.serial, accessCode: accessCode)
        conn.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch event {
                case .connected:
                    self.isConnected = true
                case .disconnected(let error):
                    self.isConnected = false
                    if let error { self.lastDeviceError = "Disconnected: \(error.localizedDescription)" }
                case .report(let payload):
                    if let status = PrintStatusReport(report: payload) {
                        self.lastStatus = status
                        self.handlePossibleFailure(status)
                    }
                }
            }
        }
        connection = conn
        connectedHost = printer.ipAddress
        connectedSerial = printer.serial
        conn.connect()
    }

    func disconnect() {
        connection?.disconnect()
        connection = nil
        isConnected = false
        connectedSerial = nil
        connectedHost = nil
        lastStatus = nil
    }

    func pausePrint() {
        do { try connection?.pausePrint() } catch { lastDeviceError = "Pause failed: \(error.localizedDescription)" }
    }

    func resumePrint() {
        do { try connection?.resumePrint() } catch { lastDeviceError = "Resume failed: \(error.localizedDescription)" }
    }

    func stopPrint() {
        do { try connection?.stopPrint() } catch { lastDeviceError = "Stop failed: \(error.localizedDescription)" }
    }

    /// Uploads `localPath`'s real bytes via `FTPSUploader` to
    /// `/sdcard/bbl_plater/`. Requires an active connection (so the host
    /// is known) — upload alone doesn't need MQTT, but this app only
    /// exposes it once a printer has been selected via Connect.
    func uploadGCode(localPath: String) async {
        guard let connectedHost else {
            lastDeviceError = "Connect to a printer before uploading."
            return
        }
        isUploading = true
        defer { isUploading = false }
        do {
            let uploader = FTPSUploader(host: connectedHost, password: accessCode)
            let fileName = URL(fileURLWithPath: localPath).lastPathComponent
            lastUploadedRemotePath = try await uploader.upload(fileAt: URL(fileURLWithPath: localPath), remoteFileName: fileName)
        } catch {
            lastDeviceError = "Upload failed: \(error.localizedDescription)"
        }
    }

    /// P7-001: fetches one real JPEG snapshot from the chamber camera
    /// (port 6000, `CameraStreamClient`). A1 hardware caps this at
    /// 1 fps (RESEARCH-P0-010.md) — a single on-demand fetch, not a
    /// continuous stream, matches that limit.
    func fetchCameraFrame() async {
        guard let connectedHost else {
            lastDeviceError = "Connect to a printer before viewing the camera."
            return
        }
        isFetchingCamera = true
        defer { isFetchingCamera = false }
        do {
            let client = CameraStreamClient(host: connectedHost, password: accessCode)
            lastCameraFrame = try await client.fetchFrame()
        } catch {
            lastDeviceError = "Camera failed: \(error.localizedDescription)"
        }
    }

    /// P7-002/P7-003/P7-004: real local failure detection from the
    /// actual MQTT status stream — posts a local `UNUserNotification`
    /// (P7-003) and, only if the user opted in, pauses the real print
    /// via MQTT (P7-004). Never fires more than once per distinct
    /// failure state.
    private func handlePossibleFailure(_ status: PrintStatusReport) {
        let isFailure = status.gcodeState == .failed || (status.printError ?? 0) != 0
        guard isFailure else {
            lastHandledFailureKey = nil
            return
        }
        let key = "\(status.gcodeState?.rawValue ?? status.rawGCodeState ?? "?")/\(status.printError ?? 0)"
        guard key != lastHandledFailureKey else { return }
        lastHandledFailureKey = key

        let content = UNMutableNotificationContent()
        content.title = "Print failure detected"
        content.body = "State: \(status.rawGCodeState ?? "unknown"), error code \(status.printError ?? 0)."
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        if autoInterventionEnabled {
            pausePrint()
        }
    }
}
