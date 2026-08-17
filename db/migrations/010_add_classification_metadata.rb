# frozen_string_literal: true

# Preserve raw Pass 2 classifications and their normalization status.
Sequel.migration do
  change do
    alter_table(:interpersonal_payloads) do
      add_column :raw_classification, String
      add_column :classification_status, String
      add_column :untrusted, TrueClass, null: false, default: false
    end
  end
end
