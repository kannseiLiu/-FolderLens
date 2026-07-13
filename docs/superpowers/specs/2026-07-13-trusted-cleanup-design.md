# FolderLens Trusted Cleanup Design

## Objective

Turn FolderLens from a read-only folder inspector into a trustworthy macOS cleanup tool. A user must be able to scan a selected folder, understand why files deserve review, select files deliberately, move the confirmed selection to the macOS Trash, and see the actual result.

This is the first product phase. Project-directory auditing and local knowledge search remain separate later phases.

## Product Principles

- FolderLens never permanently deletes files.
- FolderLens never selects files for cleanup by default.
- Large and old files are review candidates, not safe-to-delete files.
- A duplicate is called verified only after its contents match by SHA-256.
- Every cleanup action requires an explicit selection and a separate confirmation.
- Disk operations remain limited to a folder the user selected through the macOS open panel.

## User Experience

### Scan

After the user selects a folder, FolderLens scans it in the background. The interface shows the current phase, processed item count, and a cancel command. Starting a new scan, changing scan settings, navigating to another folder, or selecting another root invalidates the previous task so stale results cannot replace current results.

Deep Scan continues to skip package descendants and skips hidden files unless the user enables them. Symbolic links are not traversed.

### Cleanup Review

The existing dashboard gains a dedicated `Cleanup Review` destination rather than opening a separate wizard. It contains four candidate groups:

1. Verified duplicates
2. Large files
3. Old files
4. Temporary or cache-like files

The dashboard may keep short ranked lists for readability, but Cleanup Review uses the complete candidate collection. Each candidate shows its path, size, modification date, review reason, and confidence state. The user can preview a supported file or reveal it in Finder before selecting it.

No candidate starts selected. A persistent footer displays the selected file count and total selected size. The cleanup command remains disabled until at least one available file is selected.

Potential duplicates that have not passed content verification remain visible as potential matches but do not contribute to the conservative recoverable-space estimate.

### Confirmation And Result

Selecting `Move to Trash` opens a separate confirmation sheet. It lists every selected path, the reason it was suggested, and the total expected space. The sheet states that items will move to the macOS Trash and can be restored there.

Before execution, FolderLens checks that each file still exists and that its size and modification date match the scanned metadata. Changed or unavailable items are removed from the executable selection and explained to the user.

Trash operations execute one file at a time. A failure does not roll back files already moved successfully. The result state reports successful files, failed files with specific errors, and the space actually moved to Trash. FolderLens then rescans the current folder.

## Architecture

### ScanViewModel

A main-actor view model owns the active scan task, scan state, current result, candidate selection, cleanup confirmation, and cleanup result. `ContentView` coordinates navigation and presents state but no longer performs recursive filesystem work synchronously.

Only the currently active scan identifier may publish results. Cancellation and identifier checks prevent an older task from overwriting newer state.

### FolderScanService

`FolderScanService` enumerates metadata away from the main actor and emits progress updates. Its output contains the full set of discovered `FileItem` values. Summary ranking remains the responsibility of `FolderAnalyzer`.

The service handles unreadable entries individually where possible. A root-folder access failure ends the scan with a user-visible error; a nested-entry failure is recorded as a warning while the scan continues.

### DuplicateVerifier

Duplicate verification uses two stages:

1. Group non-empty files by byte size and retain only groups with at least two members.
2. Stream each candidate through CryptoKit SHA-256 and regroup by digest.

Hashing uses bounded chunks rather than loading complete files into memory. Files with the same size but different digests are not duplicates. Files with matching digests are verified duplicates even when their names differ.

Cancellation is checked between read chunks. If a file changes, disappears, or becomes unreadable during hashing, its verification state becomes failed or unavailable and it is excluded from verified groups.

### Cleanup Models

`CleanupCandidate` provides a common representation for duplicate, large, old, and temporary candidates. It contains the file metadata, one or more review reasons, verification state when applicable, current availability, and stable path-based identity.

A file matching multiple categories appears once in selection and size totals while retaining all applicable reasons. Summary cards may count category memberships separately, but selected and reviewable byte totals must deduplicate by standardized file path.

For each verified duplicate group, all copies are shown. FolderLens does not preselect which copy to retain or discard.

### TrashService

`TrashService` accepts only the URLs present in the final confirmed selection and calls the macOS trash API for each item. It returns a result per URL rather than one all-or-nothing result.

The app entitlement changes from user-selected read-only access to user-selected read-write access. App Sandbox remains enabled, and FolderLens receives no broad filesystem entitlement.

### Views

- `CleanupReviewView` renders category filters, complete candidate lists, selection totals, preview actions, and the cleanup command.
- `CleanupConfirmationView` performs the final user confirmation and surfaces preflight changes.
- `CleanupResultView` reports actual successes, failures, and moved size.
- Existing summary and preview views remain presentational and reuse existing file actions where practical.

## State Model

The scan state is one of idle, scanning, verifying duplicates, completed, cancelled, or failed. Progress distinguishes metadata enumeration from hashing because their item counts and cost differ.

Cleanup is separately idle, confirming, executing, or finished. Scan controls are disabled while cleanup executes. Cleanup cannot begin while the scan result is incomplete or stale.

## Error Handling

- Root access denied: end the scan and display the affected path.
- Nested entry unreadable: continue and include a warning count.
- File changed during verification: mark it unverified and exclude it from verified recoverable space.
- File changed before cleanup: remove it from execution and explain the mismatch.
- Trash operation denied or failed: leave the item selected in the result and display the localized system error.
- Partial cleanup success: preserve successful operations, report failures, then rescan.
- Scan cancelled: keep the previous completed result only when it belongs to the same root and settings; otherwise return to an empty state.

Errors must be visible in the interface. Console logging alone is not an acceptable user-facing failure mode.

## Performance Constraints

- Filesystem enumeration and hashing must not run on the main actor.
- Hashing is limited to same-size candidate groups.
- File content is read in bounded chunks.
- Progress updates are throttled enough to avoid excessive UI refreshes.
- Cancellation is cooperative and checked throughout enumeration and hashing.
- Package descendants and symbolic-link traversal remain excluded by default.

## Testing

Unit tests cover:

- cleanup category construction and reason merging
- path-deduplicated file counts and byte totals
- same-content files with different names
- same-size files with different content
- failed and unavailable verification states
- task cancellation and stale-result rejection
- preflight detection of missing or changed files
- partial trash-operation results

Integration tests create temporary directories and verify real streamed SHA-256 behavior. Trash behavior is tested through an injected filesystem adapter so normal automated tests do not modify the user's Trash.

UI tests cover an empty selection, selecting and deselecting candidates, confirmation content, cancellation, and mixed success/failure results.

## Delivery Sequence

### Increment 1: Background Scan

Move scanning out of `ContentView`, add scan state, progress, cancellation, warnings, and stale-result protection. Existing summaries and reports must remain functional.

### Increment 2: Trusted Duplicate Detection

Add full candidate collections, streamed SHA-256 verification, verified/potential labels, and accurate conservative recoverable-space estimates.

### Increment 3: Cleanup Closure

Add Cleanup Review, selection totals, preflight checks, confirmation, user-selected read-write entitlement, move-to-Trash execution, result reporting, and automatic rescan.

Each increment must pass the complete test suite and be committed and pushed independently.

## Release Acceptance Criteria

- The app remains responsive while scanning and hashing a large folder.
- A running scan can be cancelled and cannot publish stale results later.
- No file is selected automatically.
- No permanent-delete path exists.
- Only content-verified groups are described as verified duplicates.
- Potential duplicate bytes do not inflate conservative recoverable-space estimates.
- Changed or unavailable files cannot be moved using stale scan metadata.
- Every cleanup operation has a confirmation and per-file result.
- The app can move a confirmed file within the user-selected folder to Trash under App Sandbox.
- Unit, integration, and UI tests pass.

## Out Of Scope

- Permanent deletion or secure erase
- Automatic cleanup schedules
- Automatic selection of a duplicate copy
- Image perceptual hashing
- PDF similarity detection
- Treemap visualization
- AI classification, renaming, semantic search, or document question answering
- Project-directory auditing and local knowledge-base features
