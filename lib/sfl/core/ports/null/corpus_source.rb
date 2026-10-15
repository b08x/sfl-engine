# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op CorpusSource: yields zero refs. A caller that hasn't wired
        # a real source (e.g. a spec that tests dispatch in isolation)
        # processes nothing, silently.
        class CorpusSource
          include Ports::CorpusSource

          def each_ref
            enum_for(:each_ref) unless block_given?

            # yields nothing
          end

          def stats
            {}
          end
        end
      end
    end
  end
end
