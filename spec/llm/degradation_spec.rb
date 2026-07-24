# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::Degradation do
  describe ".default_interpersonal" do
    it "labels annotation_source as fallback, never llm" do
      result = described_class.default_interpersonal("c-1")

      expect(result.annotation_source).to eq("fallback")
    end

    it "carries the given reason in the reasoning field" do
      result = described_class.default_interpersonal("c-1", reason: "custom reason")

      expect(result.reasoning).to eq("custom reason")
    end

    it "is excluded from SFL::Core::Types::TRUSTED_ANNOTATION_SOURCES" do
      result = described_class.default_interpersonal("c-1")

      expect(SFL::Core::Types::TRUSTED_ANNOTATION_SOURCES).not_to include(result.annotation_source)
    end
  end

  describe ".default_textual" do
    it "returns a valid TextualPayload with unmarked theme_type" do
      result = described_class.default_textual("c-1")

      expect(result).to be_a(SFL::Core::Types::TextualPayload)
      expect(result.theme_type).to eq("unmarked")
    end
  end
end
