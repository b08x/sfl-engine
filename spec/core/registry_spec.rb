# frozen_string_literal: true

require "dry/monads"

RSpec.describe SFL::Core::Registry do
  let(:registry) { described_class.new }

  describe "#register and #resolve!" do
    it "registers a factory and resolves an instance" do
      strategy = Object.new
      registry.register(:test) { |**| strategy }
      expect(registry.resolve!(:test, kwargs: 1)).to be(strategy)
    end

    it "forwards kwargs to the factory block" do
      received = nil
      registry.register(:test) { |model:| received = model; model }
      registry.resolve!(:test, model: "gpt-4")
      expect(received).to eq("gpt-4")
    end
  end

  describe "#names" do
    it "returns an empty array when nothing is registered" do
      expect(registry.names).to eq([])
    end

    it "returns registered names as symbols" do
      registry.register(:ollama) { |**| nil }
      registry.register(:informers) { |**| nil }
      expect(registry.names).to contain_exactly(:ollama, :informers)
    end

    it "returns a frozen snapshot" do
      registry.register(:test) { |**| nil }
      snapshot = registry.names
      expect(snapshot).to be_frozen
    end
  end

  describe "#resolve!" do
    it "raises UnknownStrategyError listing valid names" do
      registry.register(:ollama) { |**| nil }
      expect { registry.resolve!(:missing) }.to raise_error(
        SFL::Core::Registry::UnknownStrategyError, /unknown strategy :missing.*valid:.*:ollama/
      )
    end
  end

  describe "#resolve" do
    it "returns Success with the instance when found" do
      strategy = Object.new
      registry.register(:test) { |**| strategy }
      result = registry.resolve(:test, x: 1)
      expect(result).to be_success
      expect(result.value!).to be(strategy)
    end

    it "returns Failure with [:unknown_strategy, name, names] when not found" do
      registry.register(:ollama) { |**| nil }
      result = registry.resolve(:missing)
      expect(result).to be_failure
      expect(result.failure).to eq([:unknown_strategy, :missing, registry.names])
    end
  end

  describe "duplicate registration" do
    it "raises DuplicateStrategyError" do
      registry.register(:test) { |**| nil }
      expect { registry.register(:test) { |**| nil } }.to raise_error(
        SFL::Core::Registry::DuplicateStrategyError, /already registered/
      )
    end
  end

  describe "thread safety" do
    it "allows concurrent reads during registration" do
      registry.register(:a) { |**| nil }
      # rubocop:disable-next ThreadSafety/NewThread -- testing thread safety
      threads = Array.new(10) { Thread.new { registry.names } }
      threads.each(&:join)
      expect(registry.names).to eq([:a])
    end
  end

  describe "no forbidden requires" do
    it "has zero requires of sequel, pgvector, net/http, dspy, informers, roda, ENV" do
      source = File.read("lib/sfl/core/registry.rb")
      expect(source).not_to match(%r{require\s+["'](sequel|pgvector|net/http|dspy|informers|roda)})
      expect(source).not_to match(/\bENV\b/)
    end
  end
end
