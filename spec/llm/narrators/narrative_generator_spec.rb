# frozen_string_literal: true

require "spec_helper"
# Analysis::NarrativeGenerator#generate names Dry::Struct::Error in a rescue clause.
require "dry-struct"

RSpec.describe SFL::LLM::Narrators::NarrativeGenerator do
  let(:credentials) { { provider: "test_provider", model: "test-model", api_key: "test-key" } }
  let(:config) do
    Struct.new(:test_provider_api_key, :test_provider_api_base, :other_provider_api_key, keyword_init: true).new
  end
  let(:raw) { double(body: { "stop_reason" => "end_turn", "content" => [{ "type" => "text" }] }) }
  let(:response) do
    instance_double(RubyLLM::Message, content: valid_text, finish_reason: :stop, content_filtered?: false, raw:)
  end
  let(:chat) do
    instance_double(RubyLLM::Chat, with_instructions: nil, with_temperature: nil, with_max_output_tokens: nil,
      with_thinking: nil, ask: response)
  end
  let(:context) { instance_double(RubyLLM::Context, chat:) }
  let(:logger) { instance_spy(SFL::Core::Ports::Logger) }
  let(:params) { {} }
  let(:valid_text) do
    <<~TEXT
      Preamble the model should not have written.

      ## Overview
      A two-person planning call.

      ## Cast and roles
      Robert gives the instructions; Ana answers them.

      **Interpersonal dynamics:**
      Imperatives run one way.

      ## Conversational arc
      Opens on scheduling, pivots at turn 4.

      ## Data quality
      Turns 7-9 are unmeasured.

      ## Takeaways
      Robert holds the facilitator role.
    TEXT
  end
  let(:generator) { described_class.new(**credentials, params:, logger:) }

  before do
    registered = RubyLLM::Provider.providers.merge(test_provider: Class.new, other_provider: Class.new)
    allow(RubyLLM::Provider).to receive(:providers).and_return(registered)
    allow(RubyLLM).to receive(:context) do |&block|
      block.call(config)
      context
    end
  end

  describe "#initialize" do
    it "accepts each variant without touching DSPy predictors" do
      %i[v0 v1 v2].each do |variant|
        expect { described_class.new(**credentials, variant:) }.not_to raise_error
      end
    end

    it "defaults to V1" do
      expect(described_class::DEFAULT_VARIANT).to eq(:v1)
    end

    it "rejects an unknown variant rather than falling back silently" do
      expect { described_class.new(**credentials, variant: :v9) }.to raise_error(ArgumentError, /unknown narrative variant/)
    end
  end

  describe "#call" do
    it "returns one String per Analysis::NarrativeGenerator section key" do
      expect(generator.call("digest").keys).to eq(SFL::Analysis::NarrativeGenerator::SECTION_KEYS)
    end

    it "parses each section body from its heading, ignoring text before the first heading" do
      expect(generator.call("digest")).to include(
        overview: "A two-person planning call.",
        cast_and_roles: "Robert gives the instructions; Ana answers them.",
        interpersonal_dynamics: "Imperatives run one way.",
        conversational_arc: "Opens on scheduling, pivots at turn 4.",
        data_quality: "Turns 7-9 are unmeasured.",
        takeaways: "Robert holds the facilitator role."
      )
    end

    it "builds a RubyLLM chat on the given provider and model, with the given key in a per-call context" do
      generator.call("digest")

      expect(RubyLLM).to have_received(:context)
      expect(config.test_provider_api_key).to eq("test-key")
      expect(context).to have_received(:chat).with(model: "test-model", provider: :test_provider,
        assume_model_exists: true)
    end

    it "sends the digest as the user message" do
      generator.call("the digest text")

      expect(chat).to have_received(:ask).with("the digest text")
    end

    it "carries the variant's instruction and the six headings into the system prompt" do
      generator.call("digest")

      expect(chat).to have_received(:with_instructions).with(a_string_including(
        SFL::LLM::Signatures::NarrativeSignatureV1.description,
        "## Overview", "## Cast and roles", "## Interpersonal dynamics",
        "## Conversational arc", "## Data quality", "## Takeaways"
      ))
    end

    it "sends no temperature and no max_tokens when the task config sets neither" do
      generator.call("digest")

      expect(chat).not_to have_received(:with_temperature)
      expect(chat).not_to have_received(:with_max_output_tokens)
    end

    it "sends no thinking setting when the task config sets no reasoning_effort" do
      generator.call("digest")

      expect(chat).not_to have_received(:with_thinking)
    end

    it "leaves the API base to RubyLLM's configuration when none is given" do
      generator.call("digest")

      expect(config.test_provider_api_base).to be_nil
    end

    context "when an API base is given" do
      let(:credentials) do
        { provider: "test_provider", model: "test-model", api_key: "test-key", api_base: "http://provider.test/v1" }
      end

      it "sets it on the per-call context" do
        generator.call("digest")

        expect(config.test_provider_api_base).to eq("http://provider.test/v1")
      end
    end

    context "when an API base is given for a provider RubyLLM has no base URL setting for" do
      let(:credentials) do
        { provider: "other_provider", model: "test-model", api_key: nil, api_base: "http://provider.test/v1" }
      end

      it "builds the chat without setting it" do
        expect { generator.call("digest") }.not_to raise_error
        expect(context).to have_received(:chat)
      end
    end

    context "when the task config sets reasoning_effort" do
      let(:params) { { reasoning_effort: "high" } }

      it "applies it as the chat's thinking effort" do
        generator.call("digest")

        expect(chat).to have_received(:with_thinking).with(effort: "high")
      end
    end

    context "when the task config sets seed" do
      let(:params) { { seed: 7, temperature: 0.2 } }

      it "raises ConfigurationError naming seed before any chat is built, instead of dropping it" do
        expect { generator.call("digest") }.to raise_error(described_class::ConfigurationError, /cannot apply seed/)
        expect(RubyLLM).not_to have_received(:context)
      end
    end

    context "when the provider request fails with a RubyLLM error" do
      before { allow(chat).to receive(:ask).and_raise(RubyLLM::BadRequestError, "temperature is not supported") }

      it "reaches the caller of Analysis::NarrativeGenerator#generate as a NarrativeError" do
        digest = instance_double(SFL::Analysis::NarrativeGenerator::Digest, to_text: "digest", source: "s")
        analysis = SFL::Analysis::NarrativeGenerator.new(narrator: generator)

        expect { analysis.generate(digest) }
          .to raise_error(SFL::Analysis::NarrativeError, /Narrative generation failed: temperature is not supported/)
      end
    end

    context "when the task config sets temperature and max_tokens" do
      let(:params) { { temperature: 0.2, max_tokens: 2048 } }

      it "applies both to the chat" do
        generator.call("digest")

        expect(chat).to have_received(:with_temperature).with(0.2)
        expect(chat).to have_received(:with_max_output_tokens).with(2048)
      end
    end

    context "when the api key is nil" do
      let(:credentials) { { provider: "other_provider", model: "other-model", api_key: nil } }

      it "builds the chat without touching a credential, leaving the key to RubyLLM's configuration" do
        generator.call("digest")

        expect(config.other_provider_api_key).to be_nil
        expect(context).to have_received(:chat).with(model: "other-model", provider: :other_provider,
          assume_model_exists: true)
      end
    end

    context "when RubyLLM does not have the provider" do
      let(:credentials) { { provider: "nonesuch", model: "test-model", api_key: "test-key" } }

      it "raises ConfigurationError before any chat is built" do
        expect { generator.call("digest") }.to raise_error(described_class::ConfigurationError, /no provider :nonesuch/)
        expect(RubyLLM).not_to have_received(:context)
      end

      it "reaches Analysis::NarrativeGenerator#generate unwrapped, so the CLI warns instead of aborting" do
        digest = instance_double(SFL::Analysis::NarrativeGenerator::Digest, to_text: "digest", source: "s")
        analysis = SFL::Analysis::NarrativeGenerator.new(narrator: generator)

        expect { analysis.generate(digest) }.to raise_error(described_class::ConfigurationError, /no provider/)
      end
    end

    context "when RubyLLM has no api key setting for the provider" do
      let(:config) { Struct.new(:other_provider_api_key, keyword_init: true).new }

      it "raises ConfigurationError naming the provider" do
        expect { generator.call("digest") }
          .to raise_error(described_class::ConfigurationError, /no api key setting for provider :test_provider/)
      end
    end

    it "logs the request and the outcome with keyword fields" do
      generator.call("digest")

      expect(logger).to have_received(:info).with("narrative request", provider: :test_provider,
        model: "test-model", variant: :v1, digest_chars: 6)
      expect(logger).to have_received(:info).with("narrative generated", provider: :test_provider,
        model: "test-model", finish_reason: :stop, content_chars: valid_text.length)
    end

    context "when the model refuses (stop_reason refusal)" do
      let(:raw) { double(body: { "stop_reason" => "refusal", "content" => [{ "type" => "text" }] }) }
      let(:response) do
        instance_double(RubyLLM::Message, content: "I can't", finish_reason: :content_filter,
          content_filtered?: true, raw:)
      end

      it "raises RefusedError naming the stop reason and content shape" do
        expect { generator.call("digest") }.to raise_error(
          described_class::RefusedError,
          %r{stop_reason :content_filter / provider refusal.*content_chars 7, block types \[text\]}
        )
      end

      it "reaches Analysis::NarrativeGenerator#generate unwrapped, so the CLI rescues it by name" do
        digest = instance_double(SFL::Analysis::NarrativeGenerator::Digest, to_text: "digest", source: "s")
        analysis = SFL::Analysis::NarrativeGenerator.new(narrator: generator)

        expect { analysis.generate(digest) }.to raise_error(described_class::RefusedError, /refusal/)
      end
    end

    context "when the response has no text" do
      let(:valid_text) { "" }
      let(:raw) { double(body: { "stop_reason" => "end_turn", "content" => [{ "type" => "thinking" }] }) }

      it "raises EmptyResponseError naming the stop reason and block types" do
        expect { generator.call("digest") }.to raise_error(
          described_class::EmptyResponseError,
          /no text.*stop_reason :stop.*content_chars 0, block types \[thinking\]/
        )
      end
    end

    context "when a required section is absent" do
      let(:valid_text) { "## Overview\nOnly this.\n" }

      it "raises MissingSectionsError from the parser, naming the missing sections" do
        expect { generator.call("digest") }.to raise_error(SFL::LLM::Narrators::SectionParser::MissingSectionsError,
          /missing sections cast_and_roles/)
      end
    end

    it "keeps the named errors inside the analysis error family" do
      expect(described_class::RefusedError.ancestors).to include(SFL::Analysis::NarrativeError)
      expect(described_class::EmptyResponseError.ancestors).to include(SFL::Analysis::NarrativeError)
      expect(described_class::ConfigurationError.ancestors).to include(SFL::Analysis::NarrativeError)
    end
  end
end
