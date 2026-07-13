# Background Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move FolderLens folder enumeration off the main actor and add visible scan progress, cancellation, warnings, and stale-result protection without changing existing analysis results.

**Architecture:** A focused `FolderScanService` performs filesystem enumeration in a detached task and reports progress through an async callback. A main-actor `FolderScanViewModel` owns the active task and scan identifier, builds the existing `FolderSummary`, and exposes state to `ContentView`. A small `ScanStatusView` presents progress, cancellation, warnings, and failures.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Foundation structured concurrency, Swift Testing, Xcode 16.2, macOS 15.0+

## Global Constraints

- Keep App Sandbox enabled and retain the current user-selected read-only entitlement in this increment.
- Do not add third-party dependencies.
- Do not change duplicate matching behavior in this increment.
- Do not add file deletion or Trash operations in this increment.
- Package descendants and symbolic-link descendants are not traversed.
- Hidden files follow `ScanSettings.includeHiddenFiles`.
- Filesystem enumeration must not run on the main actor.
- A cancelled or superseded scan must never publish stale files or summary state.
- Existing folder summary, preview, filtering, navigation, and Markdown export behavior must remain functional.

---

## File Structure

- Create `RunBoard/RunBoard/FolderScan.swift`: scan context, progress, warning, result, status, and error types.
- Create `RunBoard/RunBoard/FolderScanService.swift`: background shallow/deep enumeration and progress reporting.
- Create `RunBoard/RunBoard/FolderScanViewModel.swift`: main-actor scan lifecycle, cancellation, stale-result rejection, and summary creation.
- Create `RunBoard/RunBoard/ScanStatusView.swift`: compact progress, cancel, warning, and error presentation.
- Create `RunBoard/RunBoardTests/FolderScanServiceTests.swift`: real temporary-directory service tests.
- Create `RunBoard/RunBoardTests/FolderScanViewModelTests.swift`: deterministic cancellation and stale-result tests through a controlled scanner.
- Modify `RunBoard/RunBoard/ContentView.swift`: replace synchronous enumeration state and functions with the scan view model.
- Modify `README.md`, `CHANGELOG.md`, and `ROADMAP.md`: document the completed background scan capability.

The Xcode project uses file-system-synchronized groups, so new Swift files are discovered automatically and `project.pbxproj` must not be edited.

---

### Task 1: Scan Domain Types And Background Enumeration

**Files:**
- Create: `RunBoard/RunBoard/FolderScan.swift`
- Create: `RunBoard/RunBoard/FolderScanService.swift`
- Create: `RunBoard/RunBoardTests/FolderScanServiceTests.swift`

**Interfaces:**
- Produces: `FolderScanContext`, `FolderScanProgress`, `FolderScanWarning`, `FolderScanResult`, `FolderScanStatus`, `FolderScanError`
- Produces: `typealias FolderScanProgressHandler = @Sendable (FolderScanProgress) async -> Void`
- Produces: `protocol FolderScanning` with `scan(context:onProgress:) async throws -> FolderScanResult`
- Produces: `struct FolderScanService: FolderScanning`

- [ ] **Step 1: Write service tests using real temporary directories**

Create `RunBoard/RunBoardTests/FolderScanServiceTests.swift`:

```swift
import Foundation
import Testing
@testable import RunBoard

struct FolderScanServiceTests {
    @Test func shallowScanReturnsOnlyDirectChildren() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("root".utf8).write(to: root.appendingPathComponent("root.txt"))
        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("nested.txt"))

        let context = FolderScanContext(
            folderURL: root,
            isDeepScan: false,
            settings: .default
        )
        let result = try await FolderScanService().scan(context: context) { _ in }

        #expect(result.directChildren.map(\.name).sorted() == ["Nested", "root.txt"])
        #expect(result.analysisItems.map(\.name).sorted() == ["Nested", "root.txt"])
        #expect(result.warnings.isEmpty)
    }

    @Test func deepScanIncludesNestedFilesAndReportsFinalProgress() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        let nested = root.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("nested.txt"))

        let recorder = ProgressRecorder()
        let context = FolderScanContext(
            folderURL: root,
            isDeepScan: true,
            settings: .default
        )
        let result = try await FolderScanService().scan(context: context) { progress in
            await recorder.append(progress)
        }

        let progressValues = await recorder.values
        #expect(result.analysisItems.contains { $0.name == "nested.txt" })
        #expect(progressValues.last?.processedItemCount == result.analysisItems.count)
    }

    @Test func hiddenFilesFollowScanSettings() async throws {
        let root = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("hidden".utf8).write(to: root.appendingPathComponent(".secret"))
        try Data("visible".utf8).write(to: root.appendingPathComponent("visible.txt"))

        let skipped = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: false, settings: .default)
        ) { _ in }
        let includedSettings = ScanSettings(
            largeFileThresholdMB: 100,
            oldFileAgeYears: 1,
            includeHiddenFiles: true
        )
        let included = try await FolderScanService().scan(
            context: FolderScanContext(folderURL: root, isDeepScan: false, settings: includedSettings)
        ) { _ in }

        #expect(!skipped.directChildren.contains { $0.name == ".secret" })
        #expect(included.directChildren.contains { $0.name == ".secret" })
    }

    private func makeTemporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderLensTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

private actor ProgressRecorder {
    private(set) var values: [FolderScanProgress] = []

    func append(_ progress: FolderScanProgress) {
        values.append(progress)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify they fail to compile**

Run:

```bash
xcodebuild test \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FolderLensDerivedData \
  -only-testing:RunBoardTests/FolderScanServiceTests
```

Expected: `TEST BUILD FAILED` because `FolderScanService` and the scan domain types do not exist.

- [ ] **Step 3: Add the scan domain types**

Create `RunBoard/RunBoard/FolderScan.swift`:

```swift
import Foundation

struct FolderScanContext: Equatable {
    let folderURL: URL
    let isDeepScan: Bool
    let settings: ScanSettings
}

struct FolderScanProgress: Equatable {
    let processedItemCount: Int
}

struct FolderScanWarning: Equatable, Identifiable {
    let path: String
    let message: String

    var id: String { "\(path)|\(message)" }
}

struct FolderScanResult {
    let directChildren: [FileItem]
    let analysisItems: [FileItem]
    let warnings: [FolderScanWarning]
}

enum FolderScanStatus: Equatable {
    case idle
    case scanning
    case completed
    case cancelled
    case failed(String)
}

enum FolderScanError: LocalizedError {
    case rootUnavailable(path: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .rootUnavailable(path, reason):
            return "Could not scan \(path): \(reason)"
        }
    }
}

typealias FolderScanProgressHandler = @Sendable (FolderScanProgress) async -> Void

protocol FolderScanning {
    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult
}
```

- [ ] **Step 4: Implement background enumeration**

Create `RunBoard/RunBoard/FolderScanService.swift`:

```swift
import Foundation

struct FolderScanService: FolderScanning {
    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        try await Task.detached(priority: .userInitiated) {
            try await scanSynchronously(context: context, onProgress: onProgress)
        }.value
    }

    private func scanSynchronously(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        let manager = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = context.settings.includeHiddenFiles
            ? []
            : [.skipsHiddenFiles]
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]
        var warnings: [FolderScanWarning] = []

        let directURLs: [URL]
        do {
            directURLs = try manager.contentsOfDirectory(
                at: context.folderURL,
                includingPropertiesForKeys: Array(keys),
                options: options
            )
        } catch {
            throw FolderScanError.rootUnavailable(
                path: context.folderURL.path,
                reason: error.localizedDescription
            )
        }

        let directChildren = directURLs.compactMap { url -> FileItem? in
            do {
                return try makeFileItem(from: url, keys: keys)
            } catch {
                warnings.append(.init(path: url.path, message: error.localizedDescription))
                return nil
            }
        }
        .sorted(by: fileSort)

        guard context.isDeepScan else {
            try Task.checkCancellation()
            await onProgress(.init(processedItemCount: directChildren.count))
            return FolderScanResult(
                directChildren: directChildren,
                analysisItems: directChildren,
                warnings: warnings
            )
        }

        var deepOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !context.settings.includeHiddenFiles {
            deepOptions.insert(.skipsHiddenFiles)
        }

        guard let enumerator = manager.enumerator(
            at: context.folderURL,
            includingPropertiesForKeys: Array(keys),
            options: deepOptions,
            errorHandler: { url, error in
                warnings.append(.init(path: url.path, message: error.localizedDescription))
                return true
            }
        ) else {
            throw FolderScanError.rootUnavailable(
                path: context.folderURL.path,
                reason: "Directory enumeration is unavailable."
            )
        }

        var analysisItems: [FileItem] = []
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            do {
                let values = try url.resourceValues(forKeys: keys)
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                }
                analysisItems.append(makeFileItem(url: url, values: values))
            } catch {
                warnings.append(.init(path: url.path, message: error.localizedDescription))
            }

            if analysisItems.count.isMultiple(of: 100) {
                await onProgress(.init(processedItemCount: analysisItems.count))
            }
        }

        try Task.checkCancellation()
        await onProgress(.init(processedItemCount: analysisItems.count))
        return FolderScanResult(
            directChildren: directChildren,
            analysisItems: analysisItems,
            warnings: warnings
        )
    }

    private func makeFileItem(from url: URL, keys: Set<URLResourceKey>) throws -> FileItem {
        let values = try url.resourceValues(forKeys: keys)
        return makeFileItem(url: url, values: values)
    }

    private func makeFileItem(url: URL, values: URLResourceValues) -> FileItem {
        FileItem(
            url: url,
            name: url.lastPathComponent,
            isDirectory: values.isDirectory ?? false,
            size: Int64(values.fileSize ?? 0),
            modifiedDate: values.contentModificationDate
        )
    }

    private func fileSort(_ first: FileItem, _ second: FileItem) -> Bool {
        if first.isDirectory != second.isDirectory {
            return first.isDirectory && !second.isDirectory
        }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }
}
```

- [ ] **Step 5: Run the service tests**

Run the Step 2 command again.

Expected: `TEST SUCCEEDED` and all three `FolderScanServiceTests` pass.

- [ ] **Step 6: Commit the service**

```bash
git add RunBoard/RunBoard/FolderScan.swift RunBoard/RunBoard/FolderScanService.swift RunBoard/RunBoardTests/FolderScanServiceTests.swift
git commit -m "feat: add background folder scan service"
```

---

### Task 2: Scan Lifecycle And Stale-Result Protection

**Files:**
- Create: `RunBoard/RunBoard/FolderScanViewModel.swift`
- Create: `RunBoard/RunBoardTests/FolderScanViewModelTests.swift`

**Interfaces:**
- Consumes: `FolderScanning.scan(context:onProgress:)`
- Produces: `@MainActor final class FolderScanViewModel: ObservableObject`
- Produces: published read-only `files`, `summary`, `status`, `progress`, and `warnings`
- Produces: `start(context:)` and `cancel()`

- [ ] **Step 1: Write deterministic lifecycle tests**

Create `RunBoard/RunBoardTests/FolderScanViewModelTests.swift`:

```swift
import Foundation
import Testing
@testable import RunBoard

@MainActor
struct FolderScanViewModelTests {
    @Test func completedScanPublishesFilesSummaryAndWarnings() async throws {
        let root = URL(fileURLWithPath: "/tmp/FolderLens-A")
        let file = makeFile(root.appendingPathComponent("notes.md"), size: 12)
        let warning = FolderScanWarning(path: "/tmp/denied", message: "Denied")
        let scanner = ImmediateScanner(
            result: FolderScanResult(
                directChildren: [file],
                analysisItems: [file],
                warnings: [warning]
            )
        )
        let model = FolderScanViewModel(scanner: scanner)

        model.start(context: .init(folderURL: root, isDeepScan: false, settings: .default))
        await waitUntilSettled(model)

        #expect(model.status == .completed)
        #expect(model.files.map(\.name) == ["notes.md"])
        #expect(model.summary?.folderURL == root)
        #expect(model.warnings == [warning])
    }

    @Test func cancellingScanPublishesCancelledAndIgnoresLateCompletion() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Cancel")

        model.start(context: .init(folderURL: root, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.cancel()
        await scanner.completeRequest(
            at: 0,
            with: result(named: "late.txt", root: root)
        )
        await Task.yield()

        #expect(model.status == .cancelled)
        #expect(model.files.isEmpty)
        #expect(model.summary == nil)
    }

    @Test func newerScanWinsWhenOlderScanCompletesLast() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let firstRoot = URL(fileURLWithPath: "/tmp/FolderLens-First")
        let secondRoot = URL(fileURLWithPath: "/tmp/FolderLens-Second")

        model.start(context: .init(folderURL: firstRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(1)
        model.start(context: .init(folderURL: secondRoot, isDeepScan: true, settings: .default))
        await scanner.waitForRequestCount(2)

        await scanner.completeRequest(at: 1, with: result(named: "new.txt", root: secondRoot))
        await waitUntilSettled(model)
        await scanner.completeRequest(at: 0, with: result(named: "old.txt", root: firstRoot))
        await Task.yield()

        #expect(model.status == .completed)
        #expect(model.files.map(\.name) == ["new.txt"])
        #expect(model.summary?.folderURL == secondRoot)
    }

    @Test func cancelledRescanKeepsCompletedResultForSameContext() async throws {
        let scanner = ControlledScanner()
        let model = FolderScanViewModel(scanner: scanner)
        let root = URL(fileURLWithPath: "/tmp/FolderLens-Preserve")
        let context = FolderScanContext(folderURL: root, isDeepScan: true, settings: .default)

        model.start(context: context)
        await scanner.waitForRequestCount(1)
        await scanner.completeRequest(at: 0, with: result(named: "kept.txt", root: root))
        await waitUntilSettled(model)

        model.start(context: context)
        await scanner.waitForRequestCount(2)
        model.cancel()

        #expect(model.status == .cancelled)
        #expect(model.files.map(\.name) == ["kept.txt"])
        #expect(model.summary?.folderURL == root)
    }

    private func makeFile(_ url: URL, size: Int64) -> FileItem {
        FileItem(url: url, name: url.lastPathComponent, isDirectory: false, size: size, modifiedDate: Date())
    }

    private func waitUntilSettled(_ model: FolderScanViewModel) async {
        while model.status == .scanning {
            await Task.yield()
        }
    }

    private func result(named name: String, root: URL) -> FolderScanResult {
        let file = makeFile(root.appendingPathComponent(name), size: 10)
        return FolderScanResult(directChildren: [file], analysisItems: [file], warnings: [])
    }
}

private struct ImmediateScanner: FolderScanning {
    let result: FolderScanResult

    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        await onProgress(.init(processedItemCount: result.analysisItems.count))
        return result
    }
}

private actor ControlledScanner: FolderScanning {
    private var continuations: [CheckedContinuation<FolderScanResult, Error>?] = []

    func scan(
        context: FolderScanContext,
        onProgress: @escaping FolderScanProgressHandler
    ) async throws -> FolderScanResult {
        try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForRequestCount(_ count: Int) async {
        while continuations.count < count {
            await Task.yield()
        }
    }

    func completeRequest(at index: Int, with result: FolderScanResult) {
        continuations[index]?.resume(returning: result)
        continuations[index] = nil
    }
}
```

- [ ] **Step 2: Run the view-model tests and verify they fail to compile**

Run:

```bash
xcodebuild test \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FolderLensDerivedData \
  -only-testing:RunBoardTests/FolderScanViewModelTests
```

Expected: `TEST BUILD FAILED` because `FolderScanViewModel` does not exist.

- [ ] **Step 3: Implement the scan view model**

Create `RunBoard/RunBoard/FolderScanViewModel.swift`:

```swift
import Combine
import Foundation

@MainActor
final class FolderScanViewModel: ObservableObject {
    @Published private(set) var files: [FileItem] = []
    @Published private(set) var summary: FolderSummary?
    @Published private(set) var status: FolderScanStatus = .idle
    @Published private(set) var progress: FolderScanProgress?
    @Published private(set) var warnings: [FolderScanWarning] = []

    private let scanner: any FolderScanning
    private var scanTask: Task<Void, Never>?
    private var activeScanID = UUID()
    private var lastCompletedContext: FolderScanContext?

    init(scanner: any FolderScanning = FolderScanService()) {
        self.scanner = scanner
    }

    func start(context: FolderScanContext) {
        scanTask?.cancel()
        let scanID = UUID()
        activeScanID = scanID
        let canPreserveCompletedResult = lastCompletedContext == context && summary != nil
        if !canPreserveCompletedResult {
            files = []
            summary = nil
            warnings = []
        }
        progress = .init(processedItemCount: 0)
        status = .scanning

        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await scanner.scan(context: context) { [weak self] progress in
                    await self?.publish(progress: progress, scanID: scanID)
                }
                guard scanID == activeScanID else { return }
                files = result.directChildren
                summary = FolderAnalyzer.makeSummary(
                    for: context.folderURL,
                    files: result.analysisItems,
                    isDeepScan: context.isDeepScan,
                    settings: context.settings
                )
                warnings = result.warnings
                progress = .init(processedItemCount: result.analysisItems.count)
                status = .completed
                lastCompletedContext = context
                scanTask = nil
            } catch is CancellationError {
                guard scanID == activeScanID else { return }
                status = .cancelled
                progress = nil
                scanTask = nil
            } catch {
                guard scanID == activeScanID else { return }
                status = .failed(error.localizedDescription)
                progress = nil
                scanTask = nil
            }
        }
    }

    func cancel() {
        guard status == .scanning else { return }
        activeScanID = UUID()
        scanTask?.cancel()
        scanTask = nil
        status = .cancelled
        progress = nil
    }

    private func publish(progress newProgress: FolderScanProgress, scanID: UUID) {
        guard scanID == activeScanID, status == .scanning else { return }
        progress = newProgress
    }
}
```

- [ ] **Step 4: Run the focused view-model tests**

Run the Step 2 command again.

Expected: `TEST SUCCEEDED` and all four lifecycle tests pass.

- [ ] **Step 5: Run all unit tests**

```bash
xcodebuild test \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FolderLensDerivedData \
  -only-testing:RunBoardTests
```

Expected: `TEST SUCCEEDED`, including the six existing analyzer tests.

- [ ] **Step 6: Commit lifecycle state**

```bash
git add RunBoard/RunBoard/FolderScanViewModel.swift RunBoard/RunBoardTests/FolderScanViewModelTests.swift
git commit -m "feat: manage cancellable folder scans"
```

---

### Task 3: Progress And Cancellation UI Integration

**Files:**
- Create: `RunBoard/RunBoard/ScanStatusView.swift`
- Modify: `RunBoard/RunBoard/ContentView.swift`

**Interfaces:**
- Consumes: `FolderScanViewModel.start(context:)`, `cancel()`, `files`, `summary`, `status`, `progress`, and `warnings`
- Produces: compact `ScanStatusView` with a system progress indicator, processed count, cancel command, warning count, and retryable error text

- [ ] **Step 1: Add the scan status view**

Create `RunBoard/RunBoard/ScanStatusView.swift`:

```swift
import SwiftUI

struct ScanStatusView: View {
    let status: FolderScanStatus
    let progress: FolderScanProgress?
    let warningCount: Int
    let onCancel: () -> Void

    var body: some View {
        switch status {
        case .scanning:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Scanning \(progress?.processedItemCount ?? 0) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
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
```

- [ ] **Step 2: Replace synchronous scan state in `ContentView`**

Apply these exact structural changes in `RunBoard/RunBoard/ContentView.swift`:

```swift
@StateObject private var scanModel = FolderScanViewModel()
```

Remove the stored `files` and `currentFolderSummary` properties. Add aliases so existing filtering and report code remain readable:

```swift
private var files: [FileItem] { scanModel.files }
private var currentFolderSummary: FolderSummary? { scanModel.summary }
```

Insert the status view between `toolbarRow` and the divider in `sidebar`:

```swift
ScanStatusView(
    status: scanModel.status,
    progress: scanModel.progress,
    warningCount: scanModel.warnings.count,
    onCancel: scanModel.cancel
)
.padding(.horizontal)
```

Replace `loadFiles(from:)` with:

```swift
private func loadFiles(from folderURL: URL) {
    scanModel.start(
        context: FolderScanContext(
            folderURL: folderURL,
            isDeepScan: isDeepScanEnabled,
            settings: scanSettings
        )
    )
}
```

Remove `makeFileItem(from:)` and `scanFilesRecursively(from:)`; their responsibility now belongs to `FolderScanService`.

Disable report export while scanning so it cannot export a stale summary:

```swift
.disabled(
    currentFolderURL == nil
        || currentFolderSummary == nil
        || scanModel.status == .scanning
)
```

Apply this condition to Report. Keep Select Folder, Back, Deep Scan, and scan-setting controls enabled: using any of them starts a replacement scan and exercises stale-result protection. A new scan context clears the old file list; a rescan with the exact same folder, mode, and settings keeps the last completed result visible until replacement succeeds or the user cancels. When selecting a new folder or going back, clear `selectedFile` before starting the scan, preserving the existing behavior.

- [ ] **Step 3: Build to catch SwiftUI and concurrency integration errors**

Run:

```bash
xcodebuild build \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FolderLensDerivedData
```

Expected: `BUILD SUCCEEDED` with no concurrency or SwiftUI type-check errors.

- [ ] **Step 4: Run the full test suite**

```bash
xcodebuild test \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FolderLensDerivedData
```

Expected: `TEST SUCCEEDED` for unit, UI, and launch tests.

- [ ] **Step 5: Manually verify the user flow**

Run the app from Xcode or:

```bash
open /tmp/FolderLensDerivedData/Build/Products/Debug/RunBoard.app
```

Verify:

1. Select a folder with enough nested files to keep Deep Scan active visibly.
2. Confirm the processed count increases and the window remains interactive.
3. Cancel and confirm no later summary replaces the cancelled state.
4. Start the scan again and confirm summary, filters, preview, navigation, and Markdown export still work.
5. Enable hidden files and confirm a fresh scan starts.

- [ ] **Step 6: Commit UI integration**

```bash
git add RunBoard/RunBoard/ScanStatusView.swift RunBoard/RunBoard/ContentView.swift
git commit -m "feat: show cancellable scan progress"
```

---

### Task 4: Documentation And Increment Verification

**Files:**
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`

**Interfaces:**
- Consumes: completed background scan behavior
- Produces: accurate user documentation and a clean handoff to the trusted duplicate-detection increment

- [ ] **Step 1: Update product documentation**

In `README.md`, add these points to the appropriate Highlights and Deep Scan sections:

```markdown
- Scan large folders in the background with live item progress and cancellation.
- Keep the interface responsive while FolderLens analyzes nested content.
```

In `CHANGELOG.md` under `Unreleased / Added`, add:

```markdown
- Added background folder scanning with live processed-item progress and cancellation.
- Added protection against stale scan results when folders or settings change.
- Added user-visible scan warnings and root-folder errors.
```

In `ROADMAP.md`, remove `Add scan progress and cancellation for very large directories.` from Product Improvements and add trusted SHA-256 duplicate verification as the next active product improvement.

- [ ] **Step 2: Run repository checks and the complete suite**

```bash
git diff --check
xcodebuild test \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/FolderLensDerivedData
```

Expected: `git diff --check` prints nothing and Xcode reports `TEST SUCCEEDED`.

- [ ] **Step 3: Review the final diff for scope**

```bash
git status --short
git diff --stat
git diff -- RunBoard/RunBoard/RunBoard.entitlements RunBoard/RunBoard.xcodeproj/project.pbxproj
```

Expected: only background-scan source, tests, and documentation are changed; the entitlement and Xcode project file have no diff.

- [ ] **Step 4: Commit and push the completed increment**

```bash
git add README.md CHANGELOG.md ROADMAP.md
git commit -m "docs: document background scanning"
git push origin main
```

Expected: `main` is synchronized with `origin/main` and the worktree is clean.

---

## Completion Gate

Do not begin trusted duplicate detection until all of the following are true:

- All service and lifecycle tests pass.
- The full Xcode test suite passes.
- Manual cancellation does not allow a late summary to appear.
- Root failures and warning counts are visible in the app.
- Existing summary, preview, navigation, filters, settings, and Markdown export still work.
- No entitlement or project-file change was introduced.
- All background-scan commits are pushed to `origin/main`.
