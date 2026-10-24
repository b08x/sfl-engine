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
    it "registers all 12 leaf loader names" do
      expect(registry.names).to contain_exactly(
        :markdown, :pdf, :canvas, :image, :subtitle,
        :chatgpt_export, :claude_export, :mistral_export, :json, :csv,
        :transcription, :image_meta
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

    it "resolves :claude_export to a JsonRecordsSource" do
      loader = registry.resolve!(:claude_export, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::JsonRecordsSource)
    end

    it "resolves :mistral_export to a MistralExportSource" do
      loader = registry.resolve!(:mistral_export, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::MistralExportSource)
    end

    it "resolves :canvas to a CanvasSource" do
      loader = registry.resolve!(:canvas, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::CanvasSource)
    end

    it "resolves :transcription to a TranscriptionSource" do
      loader = registry.resolve!(:transcription, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::TranscriptionSource)
    end

    it "resolves :image_meta to an ImageMetaSource" do
      loader = registry.resolve!(:image_meta, ref: fake_ref)
      expect(loader).to be_a(SFL::Core::Loaders::ImageMetaSource)
    end

    it "forwards the optional file_id kwarg to the registered factories" do
      expect { registry.resolve!(:transcription, ref: fake_ref, file_id: "qa") }.not_to raise_error
      expect { registry.resolve!(:image_meta, ref: fake_ref, file_id: "qa") }.not_to raise_error
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

  # The catalog's whole job is verbatim argument forwarding: the factory
  # must pass the ref and every caller kwarg to the loader constructor
  # untouched — no dropped **splat, no nil-ed ref, no renamed mandatory
  # kwargs, no swallowed call. Spies pin the exact constructor call shape
  # (partial-double verification only accepts calls the real constructor
  # could take, so every kwarg below is constructor-legal).
  describe "factory argument forwarding" do
    let(:simple_sources) do
      {
        markdown: [SFL::Core::Loaders::MarkdownSource, { file_id: "qa", skip_empty: false, min_length: 7 }],
        pdf: [SFL::Core::Loaders::PdfSource, { file_id: "qa", skip_empty: false, min_length: 7 }],
        canvas: [SFL::Core::Loaders::CanvasSource, { file_id: "qa", skip_empty: false, min_length: 7 }],
        subtitle: [SFL::Core::Loaders::SubtitleSource, { file_id: "qa" }],
        transcription: [SFL::Core::Loaders::TranscriptionSource, { file_id: "qa" }],
        image_meta: [SFL::Core::Loaders::ImageMetaSource, { file_id: "qa" }],
        chatgpt_export: [SFL::Core::Loaders::ChatgptExportSource, {}],
        claude_export: [SFL::Core::Loaders::JsonRecordsSource, {}],
        mistral_export: [SFL::Core::Loaders::MistralExportSource, {}],
      }
    end

    it "forwards the ref and every constructor-legal kwarg verbatim to each simple factory" do
      simple_sources.each do |name, (source, kwargs)|
        allow(source).to receive(:new).and_return(:factory_spy)

        expect(registry.resolve!(name, ref: fake_ref, **kwargs)).to be(:factory_spy)
        expect(source).to have_received(:new).with(fake_ref, **kwargs)
      end
    end

    it "forwards the ref, the mandatory kwargs and any extras verbatim to each required-kwarg factory" do
      {
        image: [SFL::Core::Loaders::ImageSource, { chat: :a_chat, file_id: "qa" }],
        json: [SFL::Core::Loaders::JsonSource, { text_key: "text", file_id: "qa" }],
        csv: [SFL::Core::Loaders::CsvSource, { text_column: "body", file_id: "qa" }],
      }.each do |name, (source, kwargs)|
        allow(source).to receive(:new).and_return(:factory_spy)

        expect(registry.resolve!(name, ref: fake_ref, **kwargs)).to be(:factory_spy)
        expect(source).to have_received(:new).with(fake_ref, **kwargs)
      end
    end

    it "forwards optional extra kwargs alongside the mandatory ones" do
      allow(SFL::Core::Loaders::ImageSource).to receive(:new).and_return(:factory_spy)

      expect(registry.resolve!(:image, ref: fake_ref, chat: :a_chat, file_id: "qa")).to be(:factory_spy)
      expect(SFL::Core::Loaders::ImageSource).to have_received(:new).with(fake_ref, chat: :a_chat, file_id: "qa")
    end

    # A factory that dropped its **splat would silently swallow a kwarg the
    # loader does not accept; forwarding it makes the loader reject it.
    it "surfaces a kwarg the loader does not accept, instead of swallowing it" do
      (simple_sources.keys + %i[image json csv]).each do |name|
        expect { registry.resolve!(name, ref: fake_ref, bogus_kwarg: "x") }
          .to raise_error(ArgumentError), "#{name} swallowed bogus_kwarg"
      end
    end
  end
end
