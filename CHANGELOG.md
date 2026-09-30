# Changelog

All notable changes to this project will be documented in this file.

Reconstructed from this repository's git history: each release lists the
feature and fix commits it carried. Version bumps, screenshot additions
and CI syncs are left out.

## [1.1.13] - 2026-09-30

### Fixed
- The startup menu listed no games, for the same reason as Dashboard: games
  were identified by a `name` field in their `_meta.lua` that none of them
  declares, and that KOReader 2026.03 (PR #15096) deprecated in favour of the
  directory name. `Games.parseMeta()` now takes the id from the directory and
  reads the `_meta.lua` only for the label.
- `dashboard` and `opdsdir` are now treated as infrastructure, not games.

## [1.1.12] - 2026-09-30

### Fixed
- The plugin id was matched with a pattern that also matched the tail of
  `fullname`. No plugin trips it today, but a `_meta.lua` declaring a
  plain-string `fullname` before `name` would have taken the title as the id,
  and the game would not launch.
- An empty `fullname` now falls back to the id instead of rendering a blank row.

### Changed
- Game discovery and enable-state resolution move to `games.lua`.

### Added
- A spec covering the three-way enable state -- on, off, never touched -- and
  in particular that a game installed since the last toggle falls back to its
  default rather than to hidden.

## [1.1.11] - 2026-08-05

### Added
- Add ES and DE translations

### Changed
- Add issue/PR templates and CONTRIBUTING.md

## [1.1.10] - 2026-08-04

### Changed
- Symlink common/ to shared game-common

## [1.1.9] - 2026-07-29

### Fixed
- Drop deprecated name field from _meta.lua

## [1.1.6] - 2026-07-28

### Changed
- Add GPL-3.0 LICENSE

## [1.1.3] - 2026-07-21

### Added
- Add French translations via local i18n module

## [1.1.1] - 2026-07-15

### Changed
- Remove ../game-common/ fallback from package.path

## [1.1.0] - 2026-07-08

### Added
- I18n FR/EN translation + bump to 1.1.0
