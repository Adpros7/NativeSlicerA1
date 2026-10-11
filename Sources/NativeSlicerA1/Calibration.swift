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
