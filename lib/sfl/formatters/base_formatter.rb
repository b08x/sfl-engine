# frozen_string_literal: true

module SFL
  module Formatters
    # Abstract base class for result formatters.
    class BaseFormatter
      attr_reader :result

      def initialize(result)
        @result = result
      end

      # Render formatted output.
      # @return [String]
      def render
        raise NotImplementedError, "Subclasses must implement #render"
      end

      # Write formatted output to file.
      # @param path [String] Output file path
      def write_to(path)
        File.write(path, render)
      end
    end
  end
end
