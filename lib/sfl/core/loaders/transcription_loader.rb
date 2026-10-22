require 'sfl/core/loaders/source'
require 'sfl/core/types/unit'

module SFL
  module Core
    module Loaders
      class TranscriptionLoader
        include SFL::Core::Loaders::Source

        def initialize(file_path)
          @file_path = file_path
        end

        def each_unit
          File.foreach(@file_path) do |line|
            yield SFL::Core::Types::Unit.new(speaker: 'User', text: line, sent_at: Time.now)
          end
        end
      end
    end
  end
end