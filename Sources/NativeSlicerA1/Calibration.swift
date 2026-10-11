import Foundation

enum CalibrationResources {
    private static let locations: [String: (subdirectory: String, ext: String)] = [
        "flowrate-test-pass1": ("Calibration/filament_flow", "3mf"),
        "flowrate-test-pass2": ("Calibration/filament_flow", "3mf"),
        "temperature_tower": ("Calibration/temperature_tower", "stl"),
        "retraction_tower": ("Calibration/retraction", "stl"),
        "SpeedTestStructure": ("Calibration/volumetric_speed", "step"),
    ]

    static func url(named name: String) -> URL? {
        guard let location = locations[name],
              let resourceURL = Bundle.module.resourceURL
        else {
            return nil
        }
        let url = resourceURL
            .appendingPathComponent(location.subdirectory)
            .appendingPathComponent(name)
            .appendingPathExtension(location.ext)
        return FileManager.default.isReadableFile(atPath: url.path) ? url : nil
    }
}

enum CalibrationWorkflow: String, CaseIterable, Hashable {
    case flowRate
    case pressureAdvance
    case temperature
    case retraction
    case maxVolumetricSpeed
}

typealias CalibrationCapabilities = Set<CalibrationWorkflow>

extension CalibrationCapabilities {
    static let all = Set(CalibrationWorkflow.allCases)
}

struct CalibrationRequest: Equatable {
    let workflow: CalibrationWorkflow
    let start: Double
    let end: Double
    let step: Double
    let selection: SlicingJob.ProfileSelection
}

enum CalibrationError: Error, Equatable, LocalizedError {
    case invalidRange(start: Double, end: Double, step: Double)
    case unsupportedCapability(CalibrationWorkflow)

    var errorDescription: String? {
        switch self {
        case let .invalidRange(start, end, step):
            "Calibration range \(start) to \(end) with step \(step) is invalid."
        case let .unsupportedCapability(workflow):
            "\(workflow.rawValue) calibration is not supported by this printer."
        }
    }
}

enum CalibrationJob {
    static func validate(
        _ request: CalibrationRequest,
        loader: BambuProfileLoader,
        capabilities: CalibrationCapabilities
    ) throws {
        try SlicingJob.validate(request.selection, loader: loader)

        guard request.start.isFinite,
              request.end.isFinite,
              request.step.isFinite,
              request.step > 0,
              calibrationBlockCount(for: request) <= 200
        else {
            throw CalibrationError.invalidRange(
                start: request.start,
                end: request.end,
                step: request.step
            )
        }

        guard capabilities.contains(request.workflow) else {
            throw CalibrationError.unsupportedCapability(request.workflow)
        }
    }

    private static func calibrationBlockCount(for request: CalibrationRequest) -> Int {
        Int((abs(request.end - request.start) / request.step).rounded(.down)) + 1
    }
}
