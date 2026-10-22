# frozen_string_literal: true

module SFL
  module Core
    module Ports
      # Lets a person edit a piece of text in an external editor.
      module Editor
        # @param text [String]
        # @return [String] the text after editing
        def edit(text)
          raise NotImplementedError, "#{self.class} must implement #edit"
        end
      end
    end
  end
end
