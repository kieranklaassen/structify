require_relative 'lib/structify/version'

Gem::Specification.new do |spec|
  spec.name          = "structify"
  spec.version       = Structify::VERSION
  spec.authors       = ["Kieran Klaassen"]
  spec.email         = ["kieranklaassen@gmail.com"]

  spec.summary       = "Extract structured data from content using LLMs"
  spec.homepage      = "https://github.com/kieranklaassen/structify"
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 3.1"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir["*.{md,txt}", "{lib}/**/*"]
  spec.require_paths = ["lib"]

  # Runtime dependencies
  spec.add_dependency "activesupport", ">= 7.0", "< 9.0"
  spec.add_dependency "attr_json", "~> 2.1"
  spec.add_dependency "ruby_llm-schema", "~> 0.2"
end
