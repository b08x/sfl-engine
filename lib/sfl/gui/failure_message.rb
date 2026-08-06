# frozen_string_literal: true

module SFL
  module GUI
    # Turns a ReviewQueueViewModel Failure payload into something worth showing
    # a human in a msg_box_error. The payloads come straight from Core::Pipeline
    # and are structured for programs, not people — `[:pass_one_failed,
    # "sidecar crashed"]` rendered with #inspect leaks Ruby syntax into a
    # dialog. This only formats; the Result contract itself is unchanged.
    module FailureMessage
      extend self

      # @param failure [Object] the payload of a Dry::Monads::Failure
      # @return [String] e.g. "pass one failed: sidecar crashed"
      def call(failure)
        case failure
        when String then failure
        when Symbol then failure.to_s.tr("_", " ")
        when Array then failure.flatten.map { |part| call(part) }.reject(&:empty?).join(": ")
        when nil then "unknown error"
        else failure.to_s
        end
      end
    end
  end
end
