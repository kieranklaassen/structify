# Changelog

All notable changes to this project will be documented in this file.

## [0.3.4] - 2025-03-19

### Changed

- Renamed schema `title` to `name` to align with JSON Schema standards
- Added validation for schema name to ensure it matches the pattern `^[a-zA-Z0-9_-]+$`

## [0.3.3] - 2025-03-19

### Fixed

- Fixed versioning in JSON schema generation to only include fields for the current schema version
- Fields with `versions: x` no longer appear in other schema versions when generating the JSON schema

## [0.3.2] - 2025-03-17

### Added

- Added `saved_change_to_extracted_data?` method that works with the configured `default_container_attribute`

## [0.3.0] - 2025-03-17

### Added

- Added configuration system with `Structify.configure` method
- Added ability to configure default container attribute through initializer
- Changed default container attribute from `:extracted_data` to `:json_attributes`

## [0.2.0] - 2025-03-12

### Added

- New `thinking` mode option to automatically add chain of thought reasoning to LLM schemas
- When enabled, adds a `chain_of_thought` field as the first property in the generated schema

## [0.1.0] - Initial Release

- Initial release of Structify