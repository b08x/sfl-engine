# frozen_string_literal: true

module SFL
  module Boot
    # Raised by Boot.ensure_schema_current! when the database is not at the
    # latest migration, or the schema check itself fails. A Boot::Error, so
    # existing rescues still catch it; sfl-tui re-raises it instead of
    # retrying without the LLM settings.
    class SchemaError < Error; end
  end
end
