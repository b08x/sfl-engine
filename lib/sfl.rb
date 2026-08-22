# frozen_string_literal: true

require "zeitwerk"

module SFL
  class Error < StandardError; end

  # Non-standard inflections Zeitwerk's default camelizing inflector can't derive on its own.
  # "trusted_annotation_sources" => a frozen Array constant, not a class/module —
  # SCREAMING_SNAKE_CASE is the idiomatic Ruby name for it (see
  # lib/sfl/core/types/trusted_annotation_sources.rb).
  INFLECTIONS = {
    "sfl" => "SFL",
    "api" => "API",
    "cli" => "CLI",
    "tui" => "TUI",
    "gui" => "GUI",
    "llm" => "LLM",
    "trusted_annotation_sources" => "TRUSTED_ANNOTATION_SOURCES",
    "kb_content_type" => "KBContentType",
    "csv_formatter" => "CSVFormatter",
    "json_formatter" => "JSONFormatter",
    "kb_report_writer" => "KBReportWriter",
    "kb_csv_formatter" => "KBCsvFormatter",
    "kb_json_formatter" => "KBJsonFormatter",
    "kb_markdown_formatter" => "KBMarkdownFormatter",
    "kb_annotated_doc_writer" => "KBAnnotatedDocWriter",
    "kb_annotated_doc_formatter" => "KBAnnotatedDocFormatter",
    "lm_factory" => "LMFactory",
  }.freeze
  private_constant :INFLECTIONS

  def self.loader
    @loader ||= build_loader # rubocop:disable ThreadSafety/ClassInstanceVariable -- set once at require-time, before any threads exist
  end

  def self.build_loader
    Zeitwerk::Loader.new.tap do |loader|
      loader.tag = "sfl"
      loader.push_dir(__dir__)
      loader.inflector.inflect(INFLECTIONS)
      loader.ignore("#{__dir__}/sfl/gui") # glimmer-dsl-libui: opt-in require, not eager-loaded
    end
  end
  private_class_method :build_loader
end

SFL.loader.setup
