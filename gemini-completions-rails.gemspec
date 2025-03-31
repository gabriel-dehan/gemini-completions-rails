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
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", "~> 2.12"
  spec.add_dependency "faraday-typhoeus", "~> 1.1"
  spec.add_dependency "event_stream_parser", "~> 1.0"
end
