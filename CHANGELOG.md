# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Wharel-derived Arel blocks for `where`, `where.not`, `or`, `order`, `select`, `group`, `having`, `pluck`, and `pick`, with the original MIT attribution included.
- `AW::DSL` to enable private instance and class helpers with one include.
- `AW::Helpers` for optional inclusion or extension in application classes, with private predicate and function helpers.
- `AW.with_helpers` for temporary predicate helpers that preserve the caller's context, with collision checks and explicit overrides.
- `AW.build` for predicate helpers on a separate receiver, or an explicit block parameter that preserves the caller's context.
- Documentation for refinement inheritance and combining queries with a compatible wharel fork.

## [0.1.0] - 2026-09-21

### Added

- Initial release.
