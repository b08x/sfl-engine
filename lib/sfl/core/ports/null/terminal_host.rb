# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # TerminalHost for a terminal with no remote control: it opens no
        # tab and shows no image, so callers take their fallback.
        class TerminalHost
          include Ports::TerminalHost

          # rubocop:disable Naming/PredicateMethod -- the port's answer is whether the host handled the request
          def launch_tab(**) = false

          def show_image(_path) = false
          # rubocop:enable Naming/PredicateMethod
        end
      end
    end
  end
end
