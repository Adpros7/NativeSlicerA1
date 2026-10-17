import Foundation

/// Drives the Device workflow's real backing state: SSDP discovery
/// (`PrinterDiscovery`), the LAN MQTT connection (`PrinterConnection`),
/// parsed status (`PrintStatusReport`), and FTPS upload (`FTPSUploader`).
/// Every published value here comes from an actual network event, never
/// a placeholder default meant to look populated.
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

    private var discovery: PrinterDiscovery?
    private var connection: PrinterConnection?
    private var connectedHost: String?

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
                    if let status = PrintStatusReport(report: payload) { self.lastStatus = status }
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
}
