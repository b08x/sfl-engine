# frozen_string_literal: true

require "dry/monads"

module SFL
  module Core
    # Dynamic strategy registry: maps a Symbol name to a factory block.
    # Strategies (embedders, re-rankers, loaders, registers) are registered
    # at boot and resolved on demand by name — no composition root edits
    # to swap an implementation (SFL-EMB-01).
    #
    # Thread-safe: registration is guarded by a Mutex; reads see a frozen
    # snapshot of the factories at resolve time.
    #
    # Distinct from Core::ClassificationRegistry (mood/theme vocabulary
    # lookup) — no naming collision, no reconciliation needed.
    class Registry
      include Dry::Monads[:result]

      class DuplicateStrategyError < StandardError; end
      class UnknownStrategyError < StandardError; end

      def initialize
        @factories = {}
        @mutex = Mutex.new
      end

      # @param name [Symbol] unique strategy name
      # @yieldparam kwargs [Hash] keyword args forwarded to the factory
      # @yieldreturn [Object] the resolved strategy instance
      # @raise [DuplicateStrategyError] if name is already registered
      def register(name, &factory)
        @mutex.synchronize do
          raise DuplicateStrategyError, "strategy #{name.inspect} is already registered" if @factories.key?(name)

          @factories[name] = factory
        end
      end

      # @return [Array<Symbol>] registered strategy names (frozen snapshot)
      def names
        @mutex.synchronize { @factories.keys.dup.freeze }
      end

      # @param name [Symbol] strategy name
      # @param kwargs [Hash] keyword args forwarded to the factory
      # @return [Object] the resolved strategy instance
      # @raise [UnknownStrategyError] if name is not registered
      def resolve!(name, **)
        factory = @mutex.synchronize { @factories[name] }
        raise UnknownStrategyError, "unknown strategy #{name.inspect}, valid: #{names.inspect}" unless factory

        factory.call(**)
      end

      # @param name [Symbol] strategy name
      # @return [Dry::Monads::Result] Success(instance) or
      #   Failure([:unknown_strategy, name, valid_names])
      def resolve(name, **)
        factory = @mutex.synchronize { @factories[name] }
        return Failure([:unknown_strategy, name, names]) unless factory

        Success(factory.call(**))
      end
    end
  end
end
