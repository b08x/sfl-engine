# frozen_string_literal: true

# At most one provider and model assignment per task, set from the TUI's
# Models tab. Boot resolves a task's model as: the SFL_TASK_<TASK>_* env
# var, else this row, else the built-in default (Boot::TaskModelResolver).
Sequel.migration do
  change do
    create_table(:task_models) do
      primary_key :id
      String :task, null: false, unique: true
      String :provider, null: false
      String :model_id, null: false
      DateTime :updated_at, null: false, default: Sequel::CURRENT_TIMESTAMP
    end
  end
end
