# Roadmap

FolderLens is moving toward a practical, polished macOS utility for local folder understanding and cleanup review.

## Near Term

- Add real screenshots to the README.
- Rename the Xcode project, app target, and bundle metadata from `RunBoard` to `FolderLens`.
- Add a signed release build and GitHub Release notes.
- Improve the Health Score explanation inside the app.
- Add a report preview before exporting Markdown.

## Product Improvements

- Add duplicate file detection by file size and content hash.
- Add folder size ranking for nested folders.
- Add scan progress and cancellation for very large directories.
- Add export options for CSV and JSON.
- Add user-configurable thresholds for large files and old files.

## Quality Improvements

- Expand unit tests for scanning and report generation.
- Add UI tests for selecting a folder and exporting a report.
- Add GitHub Actions once the signing/build environment is finalized.
- Add a small demo fixture folder for repeatable screenshots and tests.
