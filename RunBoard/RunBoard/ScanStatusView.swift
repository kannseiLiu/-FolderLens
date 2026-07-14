import SwiftUI

struct ScanStatusView: View {
    let status: FolderScanStatus
    let progress: FolderScanProgress?
    let verificationProgress: DuplicateVerificationProgress?
    let warningCount: Int
    let onCancel: () -> Void

    static func isCancellable(_ status: FolderScanStatus) -> Bool {
        status == .scanning || status == .verifyingDuplicates
    }

    var body: some View {
        switch status {
        case .scanning, .verifyingDuplicates:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(status == .scanning
                    ? "Scanning \(progress?.processedItemCount ?? 0) items"
                    : "Verifying duplicates \(verificationProgress?.completedFileCount ?? 0) of \(verificationProgress?.totalFileCount ?? 0) files"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
                    .disabled(!Self.isCancellable(status))
            }
            .accessibilityIdentifier("scan-status")

        case .completed where warningCount > 0:
            Label(
                "Completed with \(warningCount) \(warningCount == 1 ? "warning" : "warnings")",
                systemImage: "exclamationmark.triangle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

        case .cancelled:
            Label("Scan cancelled", systemImage: "stop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)

        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

        default:
            EmptyView()
        }
    }
}
