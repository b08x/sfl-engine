# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Fake
        # TerminalHost that records each request. `capable: false` answers
        # like the null host; `error:` raises TerminalHost::Error with it.
        class TerminalHost
          include Ports::TerminalHost

          attr_reader :tabs, :images

          def initialize(capable: true, error: nil)
            @capable = capable
            @error = error
            @tabs = []
            @images = []
          end

          def launch_tab(cmd:, cwd:, title:, env: {})
            answer { @tabs << { cmd:, cwd:, title:, env: } }
          end

          def show_image(path)
            answer { @images << path }
          end

          private def answer # rubocop:disable Naming/PredicateMethod -- the port's answer
            raise Ports::TerminalHost::Error, @error if @error
            return false unless @capable

            yield
            true
          end
        end
      end
    end
  end
end
