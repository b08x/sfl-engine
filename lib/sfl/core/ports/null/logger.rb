# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Logger: every level is a silent no-op. Default for specs
        # that don't care about log output.
        class Logger
          include Ports::Logger

          def debug(_message = nil, &) = nil
          def info(_message = nil, &) = nil
          def warn(_message = nil, &) = nil
          def error(_message = nil, &) = nil
          def fatal(_message = nil, &) = nil
        end
      end
    end
  end
end
