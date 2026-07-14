# Trusted Duplicate Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically stream SHA-256 hashes after each folder scan so FolderLens labels and counts only content-verified duplicate files.

**Architecture:** Add a standalone `DuplicateVerifying` service that filters regular files by non-zero byte size and stable filesystem identity, hashes only same-size candidates after coalescing hard-linked paths to the same file identity, and returns verified groups plus per-file issues. `FolderScanViewModel` coordinates metadata scanning and verification under one scan identifier, then passes trusted results into `FolderAnalyzer`; presentational views and a testable report builder consume the final summary.

**Tech Stack:** Swift 6, SwiftUI, Foundation `FileHandle`, CryptoKit `SHA256`, Swift Testing, XCTest UI tests, Xcode 16 synchronized groups, macOS 15 deployment target.

## Global Constraints

- Duplicate verification starts automatically after every successful current-folder or Deep Scan.
- Empty files are excluded.
- Only regular files in non-empty same-size groups are opened.
- Symbolic links are excluded from duplicate verification, and hard links to the same underlying file do not inflate copy counts or recoverable bytes.
- Files without stable filesystem identity are excluded from trusted duplicate estimates.
- Hash files serially in 1 MiB chunks and never retain complete contents in memory.
- Check cooperative cancellation before each file and between chunks.
- Publish no partial summary after cancellation or scan replacement.
- Only SHA-256-identical groups contribute recoverable bytes.
- Verification is read-only; this increment cannot select, move, rename, trash, or delete files.
- Preserve package, hidden-file, symbolic-link, warning, summary, preview, and Markdown behavior from Increment 1.

---

## File Structure

- Create `RunBoard/RunBoard/DuplicateVerification.swift`: result, progress, issue, verified-group models and the `DuplicateVerifying` protocol.
- Create `RunBoard/RunBoard/DuplicateVerifier.swift`: candidate grouping, streamed CryptoKit hashing, metadata stability checks, deterministic ordering, cancellation, and progress.
- Create `RunBoard/RunBoardTests/DuplicateVerifierTests.swift`: real temporary-directory integration coverage plus deterministic cancellation/change gates.
- Modify `RunBoard/RunBoard/FolderScan.swift`: add the verification phase to scan status.
- Modify `RunBoard/RunBoard/FolderScanViewModel.swift`: coordinate scanner and verifier under one task and scan ID.
- Modify `RunBoard/RunBoardTests/FolderScanViewModelTests.swift`: verifier phase, cancellation, and stale-result tests.
- Modify `RunBoard/RunBoard/FolderAnalyzer.swift`: accept verified results and remove filename/size duplicate inference.
- Modify `RunBoard/RunBoard/FolderSummary.swift`: store verified groups/issues and use trusted wording/totals.
- Modify `RunBoard/RunBoardTests/RunBoardTests.swift`: analyzer, health, action-plan, and recoverable-byte semantics.
- Create `RunBoard/RunBoard/FolderReportBuilder.swift`: move Markdown generation into a testable value type.
- Create `RunBoard/RunBoardTests/FolderReportBuilderTests.swift`: verified terminology, digest confidence, issues, and totals.
- Modify `RunBoard/RunBoard/ContentView.swift`: call the report builder and pass verification progress into status UI.
- Modify `RunBoard/RunBoard/ScanStatusView.swift`: render hashing progress and allow cancellation.
- Modify `RunBoard/RunBoard/FolderSummaryView.swift`: verified duplicate card and verification issue section.
- Modify `RunBoard/RunBoardUITests/RunBoardUITests.swift`: retain launch smoke coverage and assert the primary scan surface remains available.
- Modify `README.md`, `CHANGELOG.md`, and `ROADMAP.md`: document trusted verification and mark the roadmap item complete.

### Task 1: Streamed SHA-256 Verification Service

**Files:**
- Create: `RunBoard/RunBoard/DuplicateVerification.swift`
- Create: `RunBoard/RunBoard/DuplicateVerifier.swift`
- Create: `RunBoard/RunBoardTests/DuplicateVerifierTests.swift`

**Interfaces:**
- Consumes: `[FileItem]` from `FolderScanResult.analysisItems`.
- Produces:

```swift
struct DuplicateVerificationProgress: Equatable, Sendable {
    let completedFileCount: Int
    let totalFileCount: Int
}

struct DuplicateVerificationIssue: Identifiable, Equatable, Sendable {
    let url: URL
    let message: String
    var id: String { "\(url.standardizedFileURL.path)|\(message)" }
}

struct DuplicateFileGroup: Identifiable, Equatable, Sendable {
    let digest: String
    let files: [FileItem]
    var id: String { digest }
    var displayName: String { files.first?.name ?? "Identical files" }
    var fileSize: Int64 { files.first?.size ?? 0 }
    var totalSize: Int64 { files.map(\.size).reduce(0, +) }
    var recoverableSize: Int64 { max(totalSize - fileSize, 0) }
}

struct DuplicateVerificationResult: Equatable, Sendable {
    let groups: [DuplicateFileGroup]
    let issues: [DuplicateVerificationIssue]
    static let empty = DuplicateVerificationResult(groups: [], issues: [])
}

typealias DuplicateVerificationProgressHandler =
    @Sendable (DuplicateVerificationProgress) async -> Void

protocol DuplicateVerifying: Sendable {
    func verify(
        files: [FileItem],
        onProgress: @escaping DuplicateVerificationProgressHandler
    ) async throws -> DuplicateVerificationResult
}
```

- `DuplicateVerifier` conforms to `DuplicateVerifying`; its production initializer defaults to `chunkSize: 1_048_576`.
- A small internal chunk-observation dependency may be injected to make mid-file mutation and cancellation tests deterministic. It must default to a no-op and must not alter production behavior.

- [ ] **Step 1: Write failing integration tests for content-based grouping**

Create tests using real temporary files:

```swift
@Test func differentNamesWithIdenticalContentsAreVerified() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try write("same payload", to: root.appendingPathComponent("report.txt"))
    let second = try write("same payload", to: root.appendingPathComponent("copy.bin"))

    let result = try await DuplicateVerifier().verify(
        files: [item(first), item(second)],
        onProgress: { _ in }
    )

    #expect(result.groups.count == 1)
    #expect(result.groups[0].files.map(\.name) == ["copy.bin", "report.txt"])
    #expect(result.groups[0].digest.count == 64)
}

@Test func equalSizesWithDifferentContentsAreNotDuplicates() async throws {
    let root = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: root) }
    let first = try write("abc", to: root.appendingPathComponent("first.txt"))
    let second = try write("xyz", to: root.appendingPathComponent("second.txt"))

    let result = try await DuplicateVerifier().verify(
        files: [item(first), item(second)],
        onProgress: { _ in }
    )

    #expect(result.groups.isEmpty)
    #expect(result.issues.isEmpty)
}
```

Also add failing tests that exclude directories, zero-byte files, and unique-size files without opening them.

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/FolderLensDuplicateVerifierRed \
  -only-testing:RunBoardTests/DuplicateVerifierTests
```

Expected: build or tests fail because `DuplicateVerifier` and its result models do not exist. Confirm the failure is from the missing feature, not test syntax.

- [ ] **Step 3: Implement candidate filtering and streamed SHA-256 hashing**

Implement the minimum service that:

```swift
let candidates = Dictionary(
    grouping: files.filter { !$0.isDirectory && !$0.isSymbolicLink && $0.size > 0 },
    by: \.size
)
.values
.filter { $0.count > 1 }
.flatMap { $0 }
.coalescingFileSystemAliases()
.sorted { $0.url.standardizedFileURL.path < $1.url.standardizedFileURL.path }
```

For each candidate, open a `FileHandle`, repeatedly call `read(upToCount:)`, update `SHA256`, check cancellation between reads, and close the handle with `defer`. Produce lowercase hexadecimal digest text with two characters per byte. Group successful `(FileItem, digest)` pairs first by original byte size and then digest, retaining only groups with at least two files.

Read `.fileSizeKey` and `.contentModificationDateKey` before and after hashing. Compare pre-hash values with the scanned `FileItem` when available and compare pre-hash with post-hash. A mismatch, missing file, or read failure creates one issue and excludes the file.

Emit `0 / totalFileCount` once before opening the first candidate, then emit
progress exactly once after every candidate finishes, whether it hashes
successfully or becomes an issue. For an empty candidate set, emit `0 / 0` and
return immediately. Sort files and issues by standardized path; sort groups by
recoverable size descending, then digest ascending.

- [ ] **Step 4: Verify GREEN for grouping and progress**

Run the focused Task 1 command again. Expected: all initial verifier tests pass.
Add assertions that progress begins with `0 / totalFileCount`, is monotonic, and
ends at `totalFileCount / totalFileCount`.

- [ ] **Step 5: Add failing tests for failures, mutation, and cancellation**

Add deterministic tests:

```swift
@Test func disappearingCandidateBecomesIssueAndValidGroupStillCompletes() async throws
@Test func fileChangedBetweenChunksIsExcludedAndReported() async throws
@Test func cancellationBetweenChunksThrowsCancellationError() async throws
@Test func threeCopiesRecoverTwoFileSizes() async throws
```

Use the injected chunk observer with an actor gate: pause after the first chunk, mutate or cancel, then release the gate. Assert no partial group is returned after cancellation and that a changed file cannot remain in a group.

- [ ] **Step 6: Run RED, implement the minimum stability hooks, then verify GREEN**

Run the same focused command before implementation and observe the expected failures. Add only the metadata checks and cooperative cancellation needed by the tests, then rerun until the complete `DuplicateVerifierTests` suite passes.

- [ ] **Step 7: Review and commit Task 1**

Run:

```bash
git diff --check
xcodebuild build -quiet \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/FolderLensDuplicateVerifierBuild \
  SWIFT_STRICT_CONCURRENCY=complete
git add RunBoard/RunBoard/DuplicateVerification.swift \
  RunBoard/RunBoard/DuplicateVerifier.swift \
  RunBoard/RunBoardTests/DuplicateVerifierTests.swift
git commit -m "feat: verify duplicate files with sha256"
```

Expected: focused tests and strict-concurrency build pass, `git diff --check` is silent, and the commit contains only Task 1 files.

### Task 2: Scan And Verification State Coordination

**Files:**
- Modify: `RunBoard/RunBoard/FolderScan.swift`
- Modify: `RunBoard/RunBoard/FolderScanViewModel.swift`
- Modify: `RunBoard/RunBoardTests/FolderScanViewModelTests.swift`

**Interfaces:**
- Consumes: `DuplicateVerifying.verify(files:onProgress:)` and `DuplicateVerificationResult` from Task 1.
- Produces:

```swift
enum FolderScanStatus: Equatable {
    case idle
    case scanning
    case verifyingDuplicates
    case completed
    case cancelled
    case failed(String)
}

@Published private(set) var verificationProgress: DuplicateVerificationProgress?
@Published private(set) var verificationIssues: [DuplicateVerificationIssue]

init(
    scanner: any FolderScanning = FolderScanService(),
    verifier: any DuplicateVerifying = DuplicateVerifier()
)
```

- [ ] **Step 1: Write failing ViewModel tests for automatic verification**

Add an `ImmediateVerifier` and a continuation-controlled `ControlledVerifier`. Cover:

```swift
@Test func completedMetadataScanAutomaticallyStartsVerification() async throws
@Test func completedVerificationPublishesVerifiedSummaryAndIssues() async throws
@Test func noCandidatesStillCompletesThroughVerifier() async throws
```

The first test must hold the verifier continuation and assert
`status == .verifyingDuplicates`, metadata files have not yet replaced the
completed summary for a new context, and verification progress starts at `0 /
0` only until the verifier publishes `0 / totalFileCount`.

- [ ] **Step 2: Run focused ViewModel tests and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/FolderLensVerificationViewModelRed \
  -only-testing:RunBoardTests/FolderScanViewModelTests
```

Expected: new tests fail because the ViewModel has no verifier phase or injected verifier.

- [ ] **Step 3: Implement one-task phase coordination**

After `scanner.scan` returns and the scan ID is still current:

```swift
status = .verifyingDuplicates
verificationProgress = .init(completedFileCount: 0, totalFileCount: 0)
let verification = try await verifier.verify(files: result.analysisItems) { [weak self] value in
    await self?.publish(verificationProgress: value, scanID: scanID)
}
guard scanID == activeScanID else { return }
```

Then build the summary with the verification result and publish files, warnings, issues, final progress, completed status, and `lastCompletedContext` together. Reset verification progress when starting metadata enumeration and when cancelling or failing.

Update `cancel()` to accept both `.scanning` and `.verifyingDuplicates` as cancellable states.

- [ ] **Step 4: Add RED tests for cancellation and stale verifier callbacks**

Add:

```swift
@Test func cancellingVerificationPublishesCancelledAndIgnoresLateCompletion() async throws
@Test func supersededVerificationCannotReplaceNewerScan() async throws
@Test func cancelledVerificationIgnoresLateProgressAndFailure() async throws
@Test func sameContextCancelledVerificationPreservesPreviousCompletedSummary() async throws
```

Verify each fails for the missing stale-result protection before adjusting production code.

- [ ] **Step 5: Implement scan-ID guards and verify GREEN**

Both progress publishers and every success/error path must guard the original scan ID and expected active phase. Rerun all `FolderScanViewModelTests`; expected: existing enumeration tests and all new verifier tests pass.

- [ ] **Step 6: Review and commit Task 2**

Run `git diff --check`, the focused ViewModel tests, and the strict-concurrency build. Commit:

```bash
git add RunBoard/RunBoard/FolderScan.swift \
  RunBoard/RunBoard/FolderScanViewModel.swift \
  RunBoard/RunBoardTests/FolderScanViewModelTests.swift
git commit -m "feat: coordinate duplicate verification scans"
```

### Task 3: Trusted Summary Semantics

**Files:**
- Modify: `RunBoard/RunBoard/FolderAnalyzer.swift`
- Modify: `RunBoard/RunBoard/FolderSummary.swift`
- Modify: `RunBoard/RunBoardTests/RunBoardTests.swift`

**Interfaces:**
- Consumes: `DuplicateVerificationResult` from Task 1.
- Changes `FolderAnalyzer.makeSummary` to accept:

```swift
static func makeSummary(
    for folderURL: URL,
    files: [FileItem],
    isDeepScan: Bool,
    settings: ScanSettings = .default,
    duplicateVerification: DuplicateVerificationResult = .empty
) -> FolderSummary
```

- `FolderSummary` stores `duplicateGroups` and `verificationIssues` from the trusted result. `DuplicateFileGroup` moves out of `FolderSummary.swift` into Task 1's model file.

- [ ] **Step 1: Replace the old heuristic test with failing trusted-input tests**

Delete `analyzerFindsPotentialDuplicateFilesByNameAndSize`. Add tests proving:

```swift
@Test func analyzerNeverInfersDuplicatesWithoutVerification() async throws
@Test func analyzerUsesVerifiedGroupsWithDifferentNames() async throws
@Test func summaryCountsOnlyVerifiedExtraCopiesAsRecoverable() async throws
@Test func verificationIssuesDoNotReduceHealthScore() async throws
```

Construct verified groups with fixed 64-character digests. Assert the action title is `Inspect 1 verified duplicate group` and its detail says the contents matched by SHA-256.

- [ ] **Step 2: Run summary tests and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/FolderLensTrustedSummaryRed \
  -only-testing:RunBoardTests/RunBoardTests
```

Expected: failures show that the analyzer still infers by name/size and summary copy still says potential.

- [ ] **Step 3: Remove heuristic grouping and consume trusted results**

Delete `FolderAnalyzer.makeDuplicateGroups`. Pass `duplicateVerification.groups` and `.issues` to `FolderSummary`. Preserve all other ranking limits and category logic.

Update summary action-plan wording and keep duplicate penalties based only on verified groups. Keep verification issues visible as data but exclude them from score and recoverable totals.

- [ ] **Step 4: Verify totals with overlapping cleanup categories**

Add a test where a verified duplicate is also large or temporary. `reviewableSize`
must sum the standardized-path union of large, old, temporary, and every file
in verified groups.

For `recoverableSize`, begin with the standardized-path union of temporary
files. For each verified group of `n` equal-size files, count how many members
`t` are already in that temporary-file set, then add
`max((n - 1) - t, 0) * fileSize`. This counts every temporary candidate once
and only adds duplicate copies not already recoverable through the temporary
category. Large and old classifications remain review-only and add no
recoverable bytes. Assert the overlapping fixture matches this exact formula.

- [ ] **Step 5: Run GREEN and commit Task 3**

Run the focused summary suite and all unit tests. Expected: all pass. Then:

```bash
git diff --check
git add RunBoard/RunBoard/FolderAnalyzer.swift \
  RunBoard/RunBoard/FolderSummary.swift \
  RunBoard/RunBoardTests/RunBoardTests.swift
git commit -m "feat: report only verified duplicate groups"
```

### Task 4: Verification UI, Markdown Report, And Product Documentation

**Files:**
- Create: `RunBoard/RunBoard/FolderReportBuilder.swift`
- Create: `RunBoard/RunBoardTests/FolderReportBuilderTests.swift`
- Modify: `RunBoard/RunBoard/ContentView.swift`
- Modify: `RunBoard/RunBoard/ScanStatusView.swift`
- Modify: `RunBoard/RunBoard/FolderSummaryView.swift`
- Modify: `RunBoard/RunBoardUITests/RunBoardUITests.swift`
- Modify: `README.md`
- Modify: `CHANGELOG.md`
- Modify: `ROADMAP.md`

**Interfaces:**
- Consumes: `FolderScanStatus.verifyingDuplicates`, `DuplicateVerificationProgress`, verified summary groups/issues.
- Produces:

```swift
struct FolderReportBuilder {
    func makeMarkdown(
        summary: FolderSummary,
        files: [FileItem],
        generatedAt: Date = Date()
    ) -> String
}
```

- [ ] **Step 1: Write failing report tests before extracting report generation**

Create tests asserting generated Markdown contains:

```text
## Verified Duplicates
SHA-256 verified
## Verification Issues
```

Assert it does not contain `Potential Duplicates`, includes all verified paths rather than only three sample paths, includes each issue path/reason, and prints the summary's conservative recoverable estimate.

- [ ] **Step 2: Run report tests and verify RED**

Run:

```bash
xcodebuild test -quiet \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/FolderLensReportRed \
  -only-testing:RunBoardTests/FolderReportBuilderTests
```

Expected: build fails because `FolderReportBuilder` does not exist.

- [ ] **Step 3: Extract and update Markdown generation**

Move the existing private Markdown composition and escaping/date helpers from `ContentView` into `FolderReportBuilder`. Preserve every existing section, then change duplicate terminology, add the confidence column and verification issues table, and include all duplicate paths.

Change `ContentView.exportMarkdownSummary()` to call:

```swift
let markdown = FolderReportBuilder().makeMarkdown(summary: summary, files: files)
```

Do not combine this task with unrelated deprecated API cleanup.

- [ ] **Step 4: Update scan and summary views**

`ScanStatusView` receives `verificationProgress` and renders:

```swift
case .verifyingDuplicates:
    Text("Verifying duplicates \(completed) of \(total)")
```

Keep the same cancel command and `scan-status` accessibility identifier.

Rename the card to `Verified Duplicates`, use `checkmark.seal.fill`, show `SHA-256 verified`, copies, per-file size, recoverable size, and every path. Add a separate `Verification Issues` card only when issues exist. Keep cards at the repository's established radius and avoid nested cards.

- [ ] **Step 5: Add focused UI assertions and run tests**

Give the select-folder button and main summary region stable accessibility identifiers if they do not already have them. Update the launch smoke test to assert the select-folder control exists after launch. Do not automate the system open panel in this increment; the existing manual fixture covers folder selection and hashing behavior.

Run report tests, all unit tests, and UI tests. Expected: report/unit tests pass; UI launch tests pass when macOS UI Automation is available. If `testmanagerd` fails before launching tests, capture the exact infrastructure error and still run `xcodebuild build` plus all focused non-UI suites separately.

- [ ] **Step 6: Update README, changelog, and roadmap**

Document automatic SHA-256 verification, bounded reads, visible progress/cancellation, issues, and conservative recoverable estimates. Move trusted SHA-256 verification from pending roadmap work to completed product behavior; leave Cleanup Closure as the next product increment.

- [ ] **Step 7: Manual acceptance verification**

Create a temporary fixture outside the repository containing:

- two differently named files with identical text
- two equal-size files with different text
- two identical files larger than one chunk

Select it in FolderLens and verify automatic phase transition, responsive UI, progress, verified-only groups, correct recoverable bytes, report terminology, and cancellation followed by a successful rescan.

- [ ] **Step 8: Final verification, review, commit, and push**

Run:

```bash
git diff --check
xcodebuild test -quiet \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/FolderLensTrustedDuplicatesFinal
git status --short
```

Request a final code review over the full increment, fix all blocking or important findings with failing regression tests first, and rerun affected suites.

Commit Task 4:

```bash
git add RunBoard/RunBoard/FolderReportBuilder.swift \
  RunBoard/RunBoardTests/FolderReportBuilderTests.swift \
  RunBoard/RunBoard/ContentView.swift \
  RunBoard/RunBoard/ScanStatusView.swift \
  RunBoard/RunBoard/FolderSummaryView.swift \
  RunBoard/RunBoardUITests/RunBoardUITests.swift \
  README.md CHANGELOG.md ROADMAP.md
git commit -m "feat: present trusted duplicate results"
git push origin main
```

Expected final state: branch is clean and synchronized with `origin/main`; only SHA-256-verified groups are labeled duplicates or counted as recoverable; cancellation and stale-result tests pass; the user-visible report agrees with the UI.
