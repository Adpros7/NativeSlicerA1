import Foundation
import Network

/// A Bambu printer announced via its LAN SSDP broadcast.
///
/// Field names mirror the vendor SSDP headers directly (see
/// RESEARCH-P0-007.md): Bambu printers broadcast a non-standard SSDP NOTIFY
/// every ~5s from UDP source port 1900 to destination ports 1990/2021 —
/// there is no official spec, this is reverse-engineered.
struct DiscoveredPrinter: Equatable {
    let serial: String          // USN
    let ipAddress: String       // Location
    let model: String?          // DevModel.bambu.com
    let name: String?           // DevName.bambu.com
    let signalStrengthDBm: Int? // DevSignal.bambu.com
    let connectionMode: String? // DevConnect.bambu.com ("lan" | "cloud")
}

/// Parses a raw SSDP NOTIFY datagram body into a `DiscoveredPrinter`.
/// Pure function, no networking — kept separate from the listener for
/// testability without binding sockets.
enum SSDPNotifyParser {
    static func parse(_ raw: String) -> DiscoveredPrinter? {
        var headers: [String: String] = [:]
        for line in raw.split(separator: "\r\n", omittingEmptySubsequences: true) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        guard
            headers["NT"] == "urn:bambulab-com:device:3dprinter:1",
            let usn = headers["USN"],
            let location = headers["Location"]
        else { return nil }

        return DiscoveredPrinter(
            serial: usn,
            ipAddress: location,
            model: headers["DevModel.bambu.com"],
            name: headers["DevName.bambu.com"],
            signalStrengthDBm: headers["DevSignal.bambu.com"].flatMap { Int($0) },
            connectionMode: headers["DevConnect.bambu.com"]
        )
    }
}

/// Listens for Bambu SSDP NOTIFY broadcasts on UDP 1990 and 2021.
@available(macOS 10.14, *)
final class PrinterDiscovery {
    private var listeners: [NWListener] = []
    private(set) var discovered: [String: DiscoveredPrinter] = [:] // keyed by serial
    var onDiscover: ((DiscoveredPrinter) -> Void)?

    func start() throws {
        for port in [UInt16(1990), UInt16(2021)] {
            guard let nwPort = NWEndpoint.Port(rawValue: port) else { continue }
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: nwPort)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: .main)
            listeners.append(listener)
        }
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {}
        }
        connection.start(queue: .main)
        receiveNext(on: connection)
    }

    private func receiveNext(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            defer {
                if error == nil { self?.receiveNext(on: connection) }
            }
            guard let self, let data, let text = String(data: data, encoding: .utf8) else { return }
            guard let printer = SSDPNotifyParser.parse(text) else { return }
            self.discovered[printer.serial] = printer
            self.onDiscover?(printer)
        }
    }
}
