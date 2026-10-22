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
      # `text` and `section_id` are the only two every source populates.
      #
      # `document_key` names the whole document this section belongs to (a
      # file path, or a conversation id inside a chat export) and
      # `source_path` the file it was read from. `parent_section_id` is the
      # section_id of the enclosing heading, or nil at the top level.
      class Unit < Dry::Struct
        attribute :section_id, Types::String
        attribute :document_key, Types::String.optional.default(nil)
        attribute :source_path, Types::String.optional.default(nil)
        attribute :parent_section_id, Types::String.optional.default(nil)
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
