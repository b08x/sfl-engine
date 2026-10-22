# frozen_string_literal: true

module SFL
  module TUI
    # Names a key event the way Messages::Key expects: "a", "A", " ",
    # "enter", "esc", "ctrl_c". Shift is dropped from single characters,
    # because the character already carries it ("A", not "shift_A").
    module KeyName
      extend self

      # @param event [#code, #modifiers]
      # @return [String]
      def call(event)
        code = event.code.to_s
        modifiers = event.modifiers.map(&:to_s)
        modifiers -= ["shift"] if code.length == 1
        modifiers.empty? ? code : "#{modifiers.join('_')}_#{code}"
      end
    end
  end
end
