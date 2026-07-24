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
    "cli" => "CLI",
    "gui" => "GUI",
    "llm" => "LLM",
    "trusted_annotation_sources" => "TRUSTED_ANNOTATION_SOURCES",
    "kb_content_type" => "KBContentType",
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
