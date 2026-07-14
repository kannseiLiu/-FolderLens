# FolderLens Trusted Duplicate Verification Design

## Objective

Replace FolderLens's filename-and-size duplicate heuristic with automatic,
streamed SHA-256 content verification. Only files whose contents are proven
identical may be labeled as duplicates or contribute to the conservative
recoverable-space estimate.

This is Increment 2 of the trusted cleanup roadmap. Moving files to Trash,
cleanup selection, and confirmation remain part of Increment 3.

## Product Decisions

- Duplicate verification starts automatically after every successful metadata
  scan, including current-folder and Deep Scan modes.
- Verification is skipped immediately when no same-size candidate group exists.
- Verification remains part of the active scan operation and can be cancelled.
- No partial verification result is published after cancellation.
- Empty files are excluded from duplicate verification and recoverable-space
  calculations.
- Files do not need matching names to be verified duplicates.
- Same-name, same-size files with different contents are not duplicates.
- Verification is read-only and never selects, moves, renames, or deletes files.

## User Experience

After metadata enumeration, FolderLens automatically enters a `Verifying
duplicates` phase when there are candidate files. The scan status displays the
number of hashed files and the total candidate count. The existing cancel
command cancels the complete operation.

The summary uses the title `Verified Duplicates`. Each verified group shows:

- the number of copies
- the size of one file
- the recoverable size when one copy is retained
- the path of every copy
- a visible `SHA-256 verified` confidence label

Files that cannot be verified are not shown as duplicates. A separate
`Verification Issues` section lists each affected path and a concise reason.
The section is omitted when there are no issues.

The Markdown report mirrors the interface terminology and includes verified
groups and verification issues. Potential or failed matches never contribute
to the recoverable-space estimate.

## Architecture

### DuplicateVerifier

`DuplicateVerifier` is an independent service that accepts the complete
collection of scanned `FileItem` values. It returns a `DuplicateVerificationResult`
containing verified groups and issues.

Verification has two stages:

1. Exclude directories and empty files, then group files by byte size. Retain
   only groups containing at least two files.
2. Stream every retained file through CryptoKit SHA-256, then regroup successful
   hashes by digest. Retain only digest groups containing at least two files.

The service processes files serially. Sequential reads are predictable on both
solid-state and mechanical disks and avoid unbounded file descriptors or disk
contention. Concurrency can be reconsidered only after profiling demonstrates a
real need.

### File Streaming

Each file is opened with `FileHandle` and read in bounded chunks. The initial
implementation uses a 1 MiB chunk size. The implementation checks task
cancellation before opening a file and between chunks.

Before hashing, the verifier reads the file's byte size and modification date.
It reads the same metadata again after hashing. A missing file, read error, size
change, or modification-date change produces a verification issue and excludes
that file from digest grouping.

### Scan Coordination

`FolderScanViewModel` owns one task covering both metadata enumeration and
duplicate verification. The flow is:

1. `FolderScanService` returns scanned file metadata.
2. `DuplicateVerifier` verifies same-size candidates and emits progress.
3. `FolderAnalyzer` builds a summary using the verification result.
4. The ViewModel publishes the final summary only if the active scan identifier
   still matches.

Starting another scan, changing settings, changing the selected folder, or
cancelling invalidates the active identifier. Late enumeration progress,
verification progress, results, and errors from an old operation are ignored.

### Models

`DuplicateFileGroup` represents only content-verified duplicates. It contains
the lowercase hexadecimal SHA-256 digest and all matching files. Its stable
identity derives from the digest rather than the display name.

`DuplicateVerificationIssue` contains the affected file URL and a user-facing
reason. Issues are sorted by standardized path so the interface and reports are
deterministic.

`DuplicateVerificationProgress` contains the completed hash count and total
candidate count. The completed count is monotonic and reaches the total when
verification completes, including files that end as issues.

The scan presentation state distinguishes metadata enumeration from duplicate
verification. Folder summaries are not published until both phases complete.

## Summary Semantics

`FolderAnalyzer` no longer creates duplicate groups from file names and sizes.
It receives verified groups and issues as inputs when constructing
`FolderSummary`.

For a verified group, recoverable bytes are:

`(file count - 1) * size of one file`

Folder health, action-plan wording, summary cards, and Markdown reports refer to
these groups as verified duplicates. Verification issues do not reduce the
health score because they are incomplete evidence, but the interface reports
them so the limitation remains visible.

## Error Handling

- Missing file: record an issue and continue with other candidates.
- File cannot be opened or read: record the localized error and continue.
- File metadata changes during hashing: record a changed-file issue and exclude
  the digest.
- Cancellation: throw `CancellationError`, publish no new summary, and preserve
  the previous completed summary only when the existing same-context rule
  permits it.
- CryptoKit or file-handle setup failure: treat it as a per-file issue rather
  than failing unrelated candidate groups.

Errors must be visible through `Verification Issues`; console-only reporting is
not sufficient.

## Performance Constraints

- Enumeration and hashing never run on the main actor.
- Only files in non-empty same-size groups are opened.
- File contents are read in 1 MiB chunks.
- Hashing is serial in this increment.
- Progress updates occur once per completed candidate file, which is naturally
  bounded by the reduced same-size candidate set.
- Cancellation is checked between chunks and between files.
- The verifier does not retain file contents in memory.

## Testing

Unit and integration tests use temporary directories and real file contents.
They cover:

- identical contents with different filenames produce one verified group
- equal sizes with different contents produce no verified group
- empty files are excluded
- groups with three or more copies calculate recoverable bytes correctly
- missing and unreadable candidates produce issues without blocking valid groups
- a file changed during hashing is excluded and reported
- progress is monotonic and completes at the candidate count
- cancellation during chunked reading throws `CancellationError`
- stale verification progress, completion, and errors cannot replace a newer scan
- summary health, action plan, and Markdown terminology use verified results only

Existing background scan, summary, report, and UI tests remain passing. Manual
verification uses a fixture containing different-name duplicates, same-size
non-duplicates, a large duplicate pair, and a file removed during verification.

## Acceptance Criteria

- Verification starts automatically after metadata scanning.
- The app remains responsive while hashing large files.
- Verification progress is visible and cancellable.
- Only SHA-256-identical files are labeled `Verified Duplicate`.
- Different-name duplicates are detected.
- Same-size different-content files are excluded.
- Failed or changed files are visible as verification issues and excluded from
  recoverable bytes.
- Recoverable bytes count only extra copies in verified groups.
- Cancelled or stale verification cannot publish a summary.
- The Markdown report matches the interface's verified terminology and totals.

## Out Of Scope

- Moving files to Trash or permanent deletion
- Automatic duplicate selection or retain/delete recommendations
- Parallel hashing
- Persistent digest caching
- Perceptual image hashing
- Similar-document detection
- AI classification, semantic search, or document question answering
