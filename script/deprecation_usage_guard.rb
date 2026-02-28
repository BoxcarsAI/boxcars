# frozen_string_literal: true

require "set"

ROOT = File.expand_path("..", __dir__)

SCAN_PATHS = %w[lib spec].freeze

PATTERNS = [
  {
    label: "Boxcars::Engines.valid_answer? legacy helper",
    regex: /Boxcars::Engines\.valid_answer\?\(/,
    allowed_files: Set.new([
      "spec/boxcars/engines_spec.rb"
    ])
  },
  {
    label: "legacy conduct access result[:answer].answer",
    regex: /result\[:answer\]\.answer\b/,
    allowed_files: Set.new([
      "lib/boxcars/conduct_result.rb",
      "spec/boxcars/boxcar_tool_spec.rb"
    ])
  }
].freeze

def ruby_files
  SCAN_PATHS.flat_map do |relative_root|
    root = File.join(ROOT, relative_root)
    Dir.glob(File.join(root, "**", "*.rb"))
  end
end

violations = []

ruby_files.each do |path|
  rel = path.delete_prefix("#{ROOT}/")
  File.readlines(path).each_with_index do |line, idx|
    PATTERNS.each do |pattern|
      next unless line.match?(pattern[:regex])
      next if pattern[:allowed_files].include?(rel)

      violations << "#{rel}:#{idx + 1} #{pattern[:label]} -> #{line.strip}"
    end
  end
end

if violations.any?
  warn "Deprecated API usage guard failed:"
  violations.each { |v| warn "  - #{v}" }
  exit 1
end

puts "Deprecated API usage guard passed."
