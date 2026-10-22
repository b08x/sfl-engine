# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # A catalog that returns fixed entries, or raises a fixed error.
        class ModelCatalog
          include Ports::ModelCatalog

          attr_reader :name

          # @param name [String]
          # @param entries [Array<Ports::ModelCatalog::Entry>]
          # @param error [Exception, nil] raised by #fetch when given
          # @param providers [Array<String>, nil] defaults to the entries' providers
          def initialize(name:, entries: [], error: nil, providers: nil)
            @name = name
            @entries = entries
            @error = error
            @providers = providers
          end

          def providers(entries) = @providers || entries.map(&:provider).uniq

          def fetch
            raise @error if @error

            @entries
          end
        end
      end
    end
  end
end
