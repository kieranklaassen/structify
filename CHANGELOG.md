# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

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