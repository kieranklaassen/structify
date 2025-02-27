# CLAUDE.md - Guidelines for Structify

## Commands
- Build: `bundle exec rake build`
- Install: `bundle exec rake install`
- Test all: `bundle exec rake spec`
- Test single file: `bundle exec rspec spec/path/to/file_spec.rb`
- Test specific example: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- Lint: `bundle exec rubocop`

## Code Style
- Use `# frozen_string_literal: true` at the top of all Ruby files
- Follow Ruby naming conventions (snake_case for methods/variables, CamelCase for classes)
- Include YARD documentation for classes and methods
- Group similar methods together
- Include descriptive RSpec tests for all functionality
- Keep methods short and focused on a single responsibility
- Use specific error classes for error handling
- Prefer explicit requires over auto-loading
- Follow ActiveSupport::Concern patterns for modules
- Keep DSL simple and intuitive for end users

## Structure
- Put core functionality in lib/structify/
- Keep implementation details private when possible
- Follow semantic versioning guidelines
- Ensure proper test coverage for all public APIs