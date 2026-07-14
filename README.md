# FolderLens

FolderLens is a lightweight macOS folder inspector that turns a local directory into a practical health report.

It helps you answer the questions Finder does not surface quickly: what is taking space, what changed recently, which files may be cleanup candidates, and what should be reviewed first.

> Note: the product name is FolderLens. The current Xcode project and scheme are still named `RunBoard` from an earlier prototype.

## Highlights

- Inspect any local folder with a native SwiftUI macOS interface.
- Browse folders, preview images and text-like files, and open items in Finder.
- Search by file name and filter by images, PDFs, videos, archives, code, text, and large files.
- Toggle Deep Scan to analyze nested folders recursively.
- Scan large folders in the background with live item progress and cancellation.
- Tune scan settings for large-file thresholds, old-file age, and hidden-file handling.
- See file type distribution, largest files, recently modified files, and safe cleanup candidates.
- Get a Folder Health Score with a prioritized action plan.
- Find folder size hotspots during Deep Scan.
- Automatically verify duplicate content with streamed SHA-256 hashing, even when file names differ.
- Follow verification progress, cancel hashing with the same scan control, and review files that could not be verified.
- Estimate reviewable space and conservative recoverable space using only verified duplicate groups.
- Export a Markdown report that includes health score, verified duplicates, verification issues, cleanup suggestions, top files, and a full file list.

## Folder Health Score

FolderLens scores a folder from 0 to 100 based on signals that usually matter during cleanup:

- large files over your selected threshold
- files not modified for longer than your selected age threshold
- temporary, cache-like, or backup files
- uncategorized file types
- whether the scan is shallow or recursive

The score is paired with a status such as Excellent, Good, Needs review, or Critical, plus an action plan that tells you what to inspect first. FolderLens never deletes files automatically.

## Scan Settings

FolderLens keeps scan settings in the sidebar so each report can match the folder you are reviewing:

- Large file threshold: choose what counts as a meaningful disk-space target.
- Old file threshold: tune how aggressively the app flags stale files.
- Hidden files: skip them for normal review, or include them when auditing project/tooling folders.

Exported Markdown reports include the active settings so the result remains explainable later.

## Deep Scan Insights

Deep Scan turns FolderLens into a more useful cleanup assistant:

- Keep the interface responsive while FolderLens analyzes nested content.
- Folder Size Hotspots rank nested folders by total file size.
- Non-empty, same-size regular-file candidates are read in bounded chunks and grouped only when their SHA-256 digests match.
- Symbolic links are excluded from duplicate verification, and hard-linked paths to the same file identity are counted once.
- Verified Duplicates show every matching path, per-file size, copy count, and recoverable size.
- Verification Issues identify files that changed or could not be read; they are not labeled or counted as duplicates.
- Hashing progress remains visible and cancellable as part of the active scan.
- Review Size estimates how much data deserves attention across large, old, temporary, and duplicate candidates.
- Recoverable estimates a conservative cleanup amount from temporary files and extra SHA-256-verified copies without double-counting overlapping paths.

## Screenshots

Screenshots will be added after the first polished release build.

Suggested screenshots:

- welcome screen
- folder summary with Health Score
- cleanup suggestions
- exported Markdown report

## Requirements

- macOS 15.0 or later
- Xcode 16.2 or later
- SwiftUI

## Getting Started

Clone the repository:

```bash
git clone https://github.com/kannseiLiu/-FolderLens.git
cd -FolderLens
```

Open the Xcode project:

```bash
open RunBoard/RunBoard.xcodeproj
```

In Xcode:

1. Select the `RunBoard` scheme.
2. Choose `My Mac` as the destination.
3. Build and run.

## Test

Run the unit tests from Terminal:

```bash
xcodebuild test \
  -project RunBoard/RunBoard.xcodeproj \
  -scheme RunBoard \
  -destination 'platform=macOS' \
  -only-testing:RunBoardTests
```

## Project Structure

```text
RunBoard/
  RunBoard.xcodeproj/       Xcode project
  RunBoard/                 SwiftUI app source
  RunBoardTests/            Unit tests
  RunBoardUITests/          UI test scaffold
```

Core files:

- `ContentView.swift`: folder selection, navigation, scanning, filtering, and Markdown export
- `FolderReportBuilder.swift`: testable Markdown report composition
- `DuplicateVerifier.swift`: bounded SHA-256 verification for non-empty, same-size regular-file candidates
- `ScanSettings.swift`: persisted scan thresholds and hidden-file policy
- `FolderSummary.swift`: summary data, health score, and action plan model
- `FolderSummaryView.swift`: dashboard, statistics, cleanup suggestions, and health overview
- `FilePreviewView.swift`: file actions and image/text previews
- `FileItem.swift`: local file metadata model

## Roadmap

See [ROADMAP.md](ROADMAP.md) for planned improvements.

## Safety

FolderLens is designed as an inspection tool. It surfaces cleanup candidates and opens files in Finder, but it does not delete or modify user files automatically.

## License

No license has been selected yet.
