# frozen_string_literal: true

# The run header: the effective provider, model and source (env, db or
# default) per task the run used, as {task => {provider, model, source}}.
# Null for runs that use no models (export) and for rows written before
# this column existed.
Sequel.migration do
  change do
    add_column :runs, :models, :jsonb
  end
end
