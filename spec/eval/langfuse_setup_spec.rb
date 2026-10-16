# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Eval::LangfuseSetup do
  let(:client) { instance_double(SFL::Eval::LangfuseClient) }
  let(:log) { StringIO.new }

  before do
    allow(client).to receive(:ensure_score_config) { |name:, **| { "id" => "cfg-#{name}", "name" => name } }
    allow(client).to receive(:list_annotation_queues).and_return([])
    allow(client).to receive(:create_annotation_queue)
  end

  it "ensures the five score configs with anchor text in the numeric descriptions" do
    described_class.new(client:, log:).call

    expect(client).to have_received(:ensure_score_config).exactly(5).times
    expect(client).to have_received(:ensure_score_config).with(hash_including(name: "tenor", description: /slang or clipped/))
    expect(client).to have_received(:ensure_score_config)
      .with(hash_including(name: "mood", categories: array_including({ label: "imperative", value: 2 })))
  end

  it "creates both queues, attaching every score config" do
    result = described_class.new(client:, log:).call

    expect(result.queues).to eq(%w[pass2-gold judge-calibration])
    expect(client).to have_received(:create_annotation_queue)
      .with(hash_including(name: "pass2-gold", score_config_ids: array_including("cfg-mood", "cfg-recap_ratio")))
  end

  it "leaves an existing queue alone" do
    allow(client).to receive(:list_annotation_queues).and_return([{ "name" => "pass2-gold" }])

    described_class.new(client:, log:).call

    expect(client).not_to have_received(:create_annotation_queue).with(hash_including(name: "pass2-gold"))
  end

  it "returns UI steps instead of failing when the API refuses queue creation" do
    allow(client).to receive(:create_annotation_queue)
      .and_raise(SFL::Eval::LangfuseClient::Error.new("404 not found", status: 404))

    result = described_class.new(client:, log:).call

    expect(result.queues).to be_empty
    expect(result.manual_steps.size).to eq(2)
    expect(result.manual_steps.first).to include("pass2-gold")
  end
end
