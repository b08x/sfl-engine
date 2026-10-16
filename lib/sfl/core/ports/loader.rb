# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Loader port: turns a ref into a stream of Types::Unit. Every
      # concrete loader (MarkdownSource, PdfSource, etc.) implements
      # #each_unit; #units is the free method built on top. Promoted
      # from the former Core::Loaders::Source duck (SFL-ING-01) so
      # loaders can be doubled without fixture files.
      module Loader
        # @yield [SFL::Core::Types::Unit]
        # @return [Enumerator] if no block given
        def each_unit
          raise NotImplementedError, "#{self.class} must implement #each_unit"
        end

        # @return [Array<SFL::Core::Types::Unit>]
        def units
          each_unit.to_a
        end
      end
    end
  end
end
