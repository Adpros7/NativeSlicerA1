import Foundation
import CocoaMQTT

/// LAN-mode MQTT connection to a Bambu A1 printer (RESEARCH-P0-007.md):
/// TLS on port 8883, fixed username `bblp`, password is the printer's LAN
/// access code, self-signed certificate (no public CA — must be trusted
/// explicitly, same as BambuStudio/OrcaSlicer/mosquitto `--insecure`).
final class PrinterConnection {
    enum Event {
        case connected
        case disconnected(Error?)
        case report([String: Any])
    }

    private let mqtt: CocoaMQTT
    private let serial: String
    var onEvent: ((Event) -> Void)?

    /// - Parameters:
    ///   - host: printer LAN IP (from SSDP `Location`).
    ///   - serial: printer USN / serial number.
    ///   - accessCode: LAN-only-mode access code shown on the printer.
    init(host: String, serial: String, accessCode: String, port: UInt16 = 8883) {
        self.serial = serial
        let clientID = "NativeSlicerA1-\(UUID().uuidString.prefix(8))"
        mqtt = CocoaMQTT(clientID: clientID, host: host, port: port)
        mqtt.username = "bblp"
        mqtt.password = accessCode
        mqtt.enableSSL = true
        mqtt.manuallyEvaluateTrust = true
        mqtt.didReceiveTrust = { _, _, completion in completion(true) } // self-signed printer cert, no public CA
        mqtt.keepAlive = 60

        mqtt.didConnectAck = { [weak self] _, ack in
            guard let self, ack == .accept else { return }
            self.mqtt.subscribe("device/\(self.serial)/report")
            self.onEvent?(.connected)
        }
        mqtt.didReceiveMessage = { [weak self] _, message, _ in
            guard let self,
                  let data = Data(message.string?.utf8 ?? "".utf8) as Data?,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return }
            self.onEvent?(.report(json))
        }
        mqtt.didDisconnect = { [weak self] _, error in
            self?.onEvent?(.disconnected(error))
        }
    }

    func connect() { _ = mqtt.connect() }
    func disconnect() { mqtt.disconnect() }

    /// Publishes a command to `device/{serial}/request`. `payload` is the
    /// top-level JSON object, e.g. `["print": ["sequence_id": "0", "command": "pause"]]`.
    func send(_ payload: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        let json = String(decoding: data, as: UTF8.self)
        mqtt.publish("device/\(serial)/request", withString: json, qos: .qos1)
    }
}
