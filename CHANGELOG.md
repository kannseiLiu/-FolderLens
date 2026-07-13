# Changelog

All notable changes to FolderLens will be documented in this file.

## Unreleased

### Added

- Added Folder Health Score to summarize folder cleanup risk from 0 to 100.
- Added health levels: Excellent, Good, Needs review, and Critical.
- Added an Action Plan that prioritizes large files, old files, temporary files, and uncategorized items.
- Added Folder Size Hotspots for ranking nested folders by disk usage.
- Added Potential Duplicates based on matching file name and file size.
- Added reviewable and recoverable space estimates.
- Added health score and action plan sections to exported Markdown reports.
- Added folder hotspot and duplicate sections to exported Markdown reports.
- Added unit tests for healthy and cleanup-heavy folder summaries.
- Added unit tests for analyzer-generated folder hotspots, duplicate groups, and space estimates.

### Changed

- Updated the folder summary dashboard to surface health and next steps near the top.
- Extracted folder summary logic into a reusable analyzer for test coverage.
- Reworked the README around real product value, usage, safety, tests, and roadmap.
