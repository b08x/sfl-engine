# frozen_string_literal: true

require "erb"

module SFL
  # Plain directory of prompt templates (track decision 9) — decoupled
  # from the ruby_llm-schema response shapes and from annotator call
  # sites. Annotators call `SFL::Prompts.render(:pass_two_annotation,
  # **vars)` rather than building prompt strings inline, so a prompt can
  # be tuned without touching the Ruby that calls the LLM.
  #
  # No separate gem/package — just lib/sfl/prompts/templates/*.txt.erb,
  # rendered with ERB#result_with_hash so template authors write plain
  # local-variable references (`<%= text %>`) instead of instance
  # variables or a bespoke binding object.
  module Prompts
    TEMPLATES_DIR = File.expand_path("prompts/templates", __dir__)

    def self.render(name, **vars)
      ERB.new(template_source(name), trim_mode: "-").result_with_hash(vars)
    end

    def self.template_source(name)
      path = File.join(TEMPLATES_DIR, "#{name}.txt.erb")
      raise ArgumentError, "no prompt template named #{name.inspect} (looked for #{path})" unless File.exist?(path)

      File.read(path)
    end
    private_class_method :template_source
  end
end
