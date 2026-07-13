# Roadmap

FolderLens is moving toward a practical, polished macOS utility for local folder understanding and cleanup review.

## Near Term

- Add real screenshots to the README.
- Rename the Xcode project and app target from `RunBoard` to `FolderLens`.
- Add a signed release build and GitHub Release notes.
- Improve the Health Score explanation inside the app.
- Add a report preview before exporting Markdown.
- Add a small demo fixture folder for repeatable screenshots and tests.

## Product Improvements

- Upgrade duplicate detection from name/size matching to optional content hashing.
- Add scan progress and cancellation for very large directories.
- Add export options for CSV and JSON.
- Add reusable scan presets for common workflows such as Downloads cleanup, project audit, and photo archive review.

## Quality Improvements

- Expand unit tests for scanning and report generation.
- Add UI tests for selecting a folder and exporting a report.
- Harden GitHub Actions once the signing/build environment is finalized.
