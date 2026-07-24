# frozen_string_literal: true

module SFL
  module Core
    module Types
      # One piece of ingestible content — a chat turn, a document section,
      # a spreadsheet row — normalized to a single owned shape (fixes D4).
      # Legacy independently reproduced an ad hoc `{name:, mes:, send_date:}`
      # turn Hash in 5+ loaders with no shared constructor or validation;
      # every Loaders::Source implementation in lib/sfl/core/loaders/
      # emits this instead, whether the source is turn-shaped (chat
      # exports, subtitles) or section-shaped (markdown, PDF, canvas).
      # Unused fields for a given source stay at their default (nil/{});
      # `text` and `document_id` are the only two every source populates.
      class Unit < Dry::Struct
        attribute :document_id, Types::String
        attribute :text, Types::String
        attribute :heading, Types::String.optional.default(nil)
        attribute :speaker, Types::String.optional.default(nil)
        attribute :is_user, Types::Bool.optional.default(nil)
        attribute :sent_at, Types::Time.optional.default(nil)
        attribute :metadata, Types::Hash.default({}.freeze)
      end
    end
  end
end
