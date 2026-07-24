# frozen_string_literal: true

require "zeitwerk"

module SFL
  class Error < StandardError; end

  def self.loader
    @loader ||= build_loader # rubocop:disable ThreadSafety/ClassInstanceVariable -- set once at require-time, before any threads exist
  end

  def self.build_loader
    Zeitwerk::Loader.new.tap do |loader|
      loader.tag = "sfl"
      loader.push_dir(__dir__)
      loader.inflector.inflect("sfl" => "SFL", "cli" => "CLI", "gui" => "GUI", "llm" => "LLM")
      loader.ignore("#{__dir__}/sfl/gui") # glimmer-dsl-libui: opt-in require, not eager-loaded
    end
  end
  private_class_method :build_loader
end

SFL.loader.setup
