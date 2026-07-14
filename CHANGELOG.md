# Changelog

All notable changes to FolderLens will be documented in this file.

## Unreleased

### Added

- Added Folder Health Score to summarize folder cleanup risk from 0 to 100.
- Added health levels: Excellent, Good, Needs review, and Critical.
- Added an Action Plan that prioritizes large files, old files, temporary files, and uncategorized items.
- Added Folder Size Hotspots for ranking nested folders by disk usage.
- Added automatic SHA-256 verification for non-empty, same-size regular-file duplicate candidates, including differently named files.
- Excluded symbolic links from duplicate verification, required stable filesystem identity for trusted duplicate estimates, and coalesced hard-linked paths so recoverable-space estimates stay conservative.
- Added bounded, chunked file reads so duplicate verification does not load entire files into memory.
- Added visible duplicate-verification progress and cancellation through the existing scan control.
- Added Verification Issues to the summary and Markdown report for files that changed or could not be hashed.
- Added reviewable and recoverable space estimates.
- Added configurable scan settings for large files, old files, and hidden files.
- Added health score and action plan sections to exported Markdown reports.
- Added folder hotspot and duplicate sections to exported Markdown reports.
- Added active scan settings to exported Markdown reports.
- Added unit tests for healthy and cleanup-heavy folder summaries.
- Added unit tests for analyzer-generated folder hotspots, duplicate groups, and space estimates.
- Added unit test coverage for custom cleanup thresholds.
- Added background folder scanning with live processed-item progress and cancellation.
- Added protection against stale scan results when folders or settings change.
- Added user-visible scan warnings and root-folder errors.
- Added focused Markdown report tests and a UI launch assertion for the folder-selection control.

### Changed

- Updated the folder summary dashboard to surface health and next steps near the top.
- Extracted folder summary logic into a reusable analyzer for test coverage.
- Updated cleanup labels and action plan text to follow the user's scan settings.
- Updated duplicate summaries and reports to use verified-only terminology, list every verified path, and count only trusted extra copies in conservative recoverable estimates.
- Extracted Markdown composition into `FolderReportBuilder` for direct unit testing.
- Set the generated app display name to FolderLens.
- Reworked the README around real product value, usage, safety, tests, and roadmap.
