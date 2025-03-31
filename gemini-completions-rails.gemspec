# frozen_string_literal: true

require_relative "lib/gemini_completions/version"

Gem::Specification.new do |spec|
  spec.name = "gemini-completions-rails"
  spec.version = GeminiCompletions::VERSION
  spec.authors = ["Gabriel Dehan"]
  spec.email = ["dehan.gabriel@gmail.com"]

  spec.summary = "API wrapper for Gemini Completions API in Rails"
  spec.description = "API wrapper for Gemini Completions API in Rails, handles streaming and tool calls"
  spec.homepage = "https://github.com/gabriel-dehan/gemini-completions-rails"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["source_code_uri"] = "https://github.com/gabriel-dehan/gemini-completions-rails"
  spec.metadata["changelog_uri"] = "https://github.com/gabriel-dehan/gemini-completions-rails/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == gemspec) ||
        f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor|Gemfile)}) ||
        f.end_with?(".gem")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.12"
  spec.add_dependency "faraday-typhoeus", "~> 1.1"
  spec.add_dependency "event_stream_parser", "~> 1.0"
end
