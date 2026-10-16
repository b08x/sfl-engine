# frozen_string_literal: true

require "dry/monads"

RSpec.describe SFL::Core::Loaders::Catalog do
  let(:registry) { SFL::Core::Registry.new }
  let(:fake_ref) { build_fake_ref }

  before { described_class.register_into(registry) }

  def build_fake_ref
    ref_class = Struct.new(:read, :name, :extension, :content_identity, :size_bytes, :mtime, :source_id, :path_hint, keyword_init: true)
    ref_class.new(
      read: "# Hello\n\nSome content here.",
      name: "sample",
      extension: ".md",
      content_identity: "sample.md:27",
      size_bytes: 27,
      mtime: nil,
      source_id: "fake",
      path_hint: nil
    )
  end

  describe "register_into" do
    it "registers all 10 leaf loader names" do
      expect(registry.names).to contain_exactly(
        :markdown, :pdf, :canvas, :image, :subtitle,
        :chatgpt_export, :claude_export, :mistral_export, :json, :csv
      )
    end

    it "does not register composite loader names" do
      names = registry.names
      expect(names).not_to include(:conversation)
      expect(names).not_to include(:documentation)
      expect(names).not_to include(:knowledge_base)
    end
  end

  describe "resolve! with valid names" do
    it "resolves :markdown to a MarkdownSource" do
      loader = registry.resolve!(:markdown, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::MarkdownSource)
    end

    it "resolves :subtitle to a SubtitleSource" do
      loader = registry.resolve!(:subtitle, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::SubtitleSource)
    end

    it "resolves :chatgpt_export to a ChatgptExportSource" do
      loader = registry.resolve!(:chatgpt_export, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::ChatgptExportSource)
    end

    it "resolves :claude_export to a ClaudeExportSource" do
      loader = registry.resolve!(:claude_export, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::ClaudeExportSource)
    end

    it "resolves :mistral_export to a MistralExportSource" do
      loader = registry.resolve!(:mistral_export, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::MistralExportSource)
    end

    it "resolves :canvas to a CanvasSource" do
      loader = registry.resolve!(:canvas, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::CanvasSource)
    end

    it "resolves :pdf to a PdfSource" do
      loader = registry.resolve!(:pdf, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::PdfSource)
    end

    it "forwards optional kwargs to the constructor" do
      loader = registry.resolve!(:markdown, ref: fake_ref, skip_empty: false, min_length: 10)
      expect(loader).to be_a(SFL::Core::Loaders::MarkdownSource)
    end
  end

  describe "fail-fast on missing required kwargs" do
    it "raises ArgumentError for :image without chat:" do
      expect { registry.resolve!(:image, ref: fake_ref) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for :json without text_key:" do
      expect { registry.resolve!(:json, ref: fake_ref) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for :csv without text_column:" do
      expect { registry.resolve!(:csv, ref: fake_ref) }.to raise_error(ArgumentError)
    end
  end

  describe "resolve (monadic) failure" do
    it "returns Failure for an unknown loader name" do
      result = registry.resolve(:nope, ref: fake_ref)
      expect(result).to be_failure
      expect(result.failure).to eq([:unknown_strategy, :nope, registry.names])
    end
  end

  describe "consumes Core::Registry verbatim" do
    it "does not define its own registry behavior" do
      source = File.read("lib/sfl/core/loaders/catalog.rb")
      expect(source).not_to match(/class.*Registry/)
      expect(source).not_to include("def resolve")
      expect(source).not_to match(/def register\b/)
    end
  end
end
