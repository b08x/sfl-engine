# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Fan-out adapter: forwards every call and its fields to each child
      # logger. A child that raises is reported on $stderr and skipped, so one
      # failing target cannot stop the others.
      class MultiLogger
        include Ports::Logger

        def initialize(children)
          @children = children.freeze
        end

        %i[debug info warn error fatal].each do |severity|
          define_method(severity) do |message = nil, **fields, &block|
            @children.each { |child| forward(child, severity, message, fields, block) }
            nil
          end
        end

        private def forward(child, severity, message, fields, block)
          child.public_send(severity, message, **fields, &block)
        rescue => e
          Kernel.warn("[MultiLogger] #{child.class} failed on #{severity}: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
