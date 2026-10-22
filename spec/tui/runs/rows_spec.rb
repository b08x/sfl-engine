# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::TUI::Runs::Rows do
  let(:now) { Time.new(2026, 10, 17, 12, 0, 0) }
  let(:row) do
    {
      run_id: "0123456789abcdef",
      kind: "export",
      collection: nil,
      state: "stalled",
      done: 3,
      total: 4,
      failed: 1,
      current_item: "a.md",
      started_at: now - 30,
    }
  end

  it "turns a run row into cells (fact 53)" do
    expect(described_class.cell(row, now)).to eq(["11:59:30", "export", "-", "stalled", "3/4 (75%)", "1", "a.md", "01234567"])
    expect(described_class.cells([row], now:).size).to eq(1)
  end

  it "shows the date for a run started on an earlier day, and dashes for no start" do
    expect(described_class.started(now - 86_400, now)).to eq("2026-10-16 12:00")
    expect(described_class.started(nil, now)).to eq("-")
  end

  it "shows progress without a total" do
    expect(described_class.progress(done: 0, total: 0)).to eq("0/0")
  end

  it "marks stalled, dead and failed runs for attention" do
    expect(%w[stalled dead failed running finished].map { |state| described_class.attention?(state:) })
      .to eq([true, true, true, false, false])
  end
end
