import Foundation

struct ScanSettings: Equatable {
    var largeFileThresholdMB: Int
    var oldFileAgeYears: Int
    var includeHiddenFiles: Bool

    static let `default` = ScanSettings(
        largeFileThresholdMB: 100,
        oldFileAgeYears: 1,
        includeHiddenFiles: false
    )

    var largeFileThresholdBytes: Int64 {
        Int64(max(1, largeFileThresholdMB)) * 1024 * 1024
    }

    var oldFileCutoffDate: Date {
        Calendar.current.date(
            byAdding: .year,
            value: -max(0, oldFileAgeYears),
            to: Date()
        ) ?? .distantPast
    }
}
