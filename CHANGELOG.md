# Changelog

All notable changes to VoidAuras are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- **Taint error on `UNIT_AURA`** (`Triggers/AuraTrigger.lua`): `aura.isHelpful` and `aura.isHarmful` are secret/tainted booleans in WoW 12.x and cannot be used in comparisons by addon code. Both `HandleAddedAura` and `HandleUpdatedAura` were hitting this. Replaced all `isHelpful` comparisons with `FindFilterForInstance`, which probes `C_UnitAuras.GetAuraDataByIndex` with explicit `"HELPFUL"`/`"HARMFUL"` filter strings — an untainted API path. Updates use the existing state bucket as an O(1) fast path and only fall back to the index scan for unknown instances.

---

## [0.1.0] — 2026-04-03

### Added

- Initial release: aura, cooldown (disabled — WoW 12.x), and resource triggers.
- Icon, bar, and text display types with per-aura configuration.
- `/va` config panel with aura list, Trigger tab, Display tab, solo mode, and spell-ID overlay.
- SavedVariables (`VoidAurasSaved`) with global and per-character profiles.
- Private aura support via `UNIT_AURA` incremental API (`isPrivateAura`).
