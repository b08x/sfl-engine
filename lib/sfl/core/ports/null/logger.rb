# frozen_string_literal: true

module SFL
  module Core
    module Ports
      module Null
        # No-op Logger: every level is a silent no-op. Default for specs
        # that don't care about log output.
        class Logger
          include Ports::Logger

          def debug(_message = nil, **_fields, &) = nil
          def info(_message = nil, **_fields, &) = nil
          def warn(_message = nil, **_fields, &) = nil
          def error(_message = nil, **_fields, &) = nil
          def fatal(_message = nil, **_fields, &) = nil
        end
      end
    end
  end
end
