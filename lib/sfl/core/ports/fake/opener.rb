# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # Opener that records each path it was asked to open.
        class Opener
          include Ports::Opener

          attr_reader :opened

          def initialize
            @opened = []
          end

          def open(path)
            @opened << path
            nil
          end
        end
      end
    end
  end
end
