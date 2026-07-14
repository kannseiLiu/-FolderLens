# Roadmap

FolderLens is moving toward a practical, polished macOS utility for local folder understanding and cleanup review.

## Completed Product Behavior

- Automatically verify non-empty, same-size regular-file candidates with bounded, streamed SHA-256 reads.
- Keep duplicate estimates conservative by excluding symbolic links and counting hard-linked paths to the same file identity once.
- Show verification progress and cancellation as part of the scan lifecycle.
- Label and count only SHA-256-matching files as duplicates, while surfacing per-file verification issues.
- Use verified groups for conservative recoverable-space estimates and Markdown reports.

## Near Term

- Add real screenshots to the README.
- Rename the Xcode project and app target from `RunBoard` to `FolderLens`.
- Add a signed release build and GitHub Release notes.
- Improve the Health Score explanation inside the app.
- Add a report preview before exporting Markdown.
- Add a small demo fixture folder for repeatable screenshots and tests.

## Product Improvements

- Add Cleanup Closure: review selections and totals, run preflight checks and confirmation, move approved files to Trash, report results, and rescan automatically.
- Add export options for CSV and JSON.
- Add reusable scan presets for common workflows such as Downloads cleanup, project audit, and photo archive review.

## Quality Improvements

- Expand unit tests for scanning and report edge cases.
- Add UI tests for selecting a folder and exporting a report.
- Harden GitHub Actions once the signing/build environment is finalized.
