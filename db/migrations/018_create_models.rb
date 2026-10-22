# frozen_string_literal: true

# One row per provider model, filled by `rake models:refresh` and the TUI's
# Models tab from the ruby_llm registry and the Ollama and OpenRouter
# listings (Store::PgModelRepository#sync). A model missing from its
# provider's latest listing gets `available = false`; the row is kept so a
# task assigned to it can show a warning.
Sequel.migration do
  change do
    create_table(:models) do
      primary_key :id
      String :provider, null: false
      String :model_id, null: false
      String :name
      Integer :context_window
      column :capabilities, :jsonb, null: false, default: Sequel.lit("'[]'::jsonb")
      column :pricing, :jsonb, null: false, default: Sequel.lit("'{}'::jsonb")
      TrueClass :available, null: false, default: true
      DateTime :fetched_at, null: false, default: Sequel::CURRENT_TIMESTAMP

      index %i[provider model_id], unique: true
    end
  end
end
