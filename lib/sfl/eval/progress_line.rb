# frozen_string_literal: true

module SFL
  module Eval
    # Parser for the progress line the analysis engine writes to stderr after
    # each finished turn: `progress turn=N total=M`. Shared by the rake task so
    # the format lives in one place.
    module ProgressLine
      PATTERN = /\Aprogress turn=(\d+) total=(\d+)\s*\z/

      # @param line [String, nil]
      # @return [Hash{Symbol => Integer}, nil] `{turn:, total:}`, or nil for any other text
      module_function def parse(line)
        match = PATTERN.match(line.to_s)
        match && { turn: match[1].to_i, total: match[2].to_i }
      end
    end
  end
end
