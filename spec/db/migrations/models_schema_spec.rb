# frozen_string_literal: true

require "spec_helper"

# Facts 54, 57 and 65: the columns of the models and task_models tables and
# the runs table's model header.
RSpec.describe "migrations 018 to 020" do # rubocop:disable RSpec/DescribeClass -- migrations, not a class
  let(:db) { SFL::Store::StoreTestDb.db }

  def columns(table) = db.schema(table, reload: true).map(&:first)

  before { SFL::Store::StoreTestDb.clean! }

  it "gives models a provider, model id, context window, capabilities, pricing, availability and fetch time" do
    expect(columns(:models)).to include(
      :provider, :model_id, :name, :context_window, :capabilities, :pricing, :available, :fetched_at
    )
    expect(db.indexes(:models)).to include(models_provider_model_id_index: hash_including(unique: true))
  end

  it "allows one task_models row per task" do
    expect(columns(:task_models)).to include(:task, :provider, :model_id, :updated_at)
    db[:task_models].insert(task: "embedding", provider: "ollama", model_id: "a")

    expect { db[:task_models].insert(task: "embedding", provider: "ollama", model_id: "b") }
      .to raise_error(Sequel::UniqueConstraintViolation)
  end

  it "gives runs a models column for the run header" do
    expect(columns(:runs)).to include(:models)
  end
end
