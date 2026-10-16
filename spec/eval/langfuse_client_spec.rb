# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Eval::LangfuseClient do
  let(:calls) { [] }
  let(:responses) { [] }
  let(:transport) do
    lambda do |method, url, headers, body|
      calls << { method:, url:, headers:, body: body && JSON.parse(body) }
      responses.shift || SFL::Eval::LangfuseClient::Response.new(200, "{}")
    end
  end
  let(:client) do
    described_class.new(host: "http://lf.test:3000/", public_key: "pk", secret_key: "sk", transport:)
  end

  def reply(status, payload)
    responses << SFL::Eval::LangfuseClient::Response.new(status, JSON.generate(payload))
  end

  it "sends Basic auth and JSON headers and strips the trailing slash from the host" do
    client.list_datasets

    expect(calls.first[:url]).to eq("http://lf.test:3000/api/public/v2/datasets?page=1&limit=50")
    expect(calls.first[:headers]["Authorization"]).to eq("Basic #{Base64.strict_encode64('pk:sk')}")
    expect(calls.first[:headers]["Content-Type"]).to eq("application/json")
  end

  it "upserts a dataset by name" do
    client.upsert_dataset(name: "sfl-narrative-digests", description: "d", metadata: { goal: "g" })

    expect(calls.first).to include(method: :post, url: "http://lf.test:3000/api/public/v2/datasets")
    expect(calls.first[:body]).to eq("name" => "sfl-narrative-digests", "description" => "d", "metadata" => { "goal" => "g" })
  end

  it "upserts a dataset item under a caller-chosen id, which makes reruns idempotent" do
    client.upsert_dataset_item(dataset: "ds", id: "nd-1", input: { "digest" => "x" }, metadata: { n: 1 })

    expect(calls.first[:url]).to eq("http://lf.test:3000/api/public/dataset-items")
    expect(calls.first[:body]).to include("datasetName" => "ds", "id" => "nd-1", "input" => { "digest" => "x" })
    expect(calls.first[:body]).not_to have_key("expectedOutput")
  end

  it "creates a score config only when its name is absent, so setup can be rerun" do
    reply(200, { data: [{ name: "mood" }], meta: { totalPages: 1 } })

    client.ensure_score_config(name: "mood", data_type: "CATEGORICAL", categories: [{ label: "declarative", value: 0 }])

    expect(calls.map { |c| c[:method] }).to eq([:get])
  end

  it "posts a missing score config with its categories" do
    reply(200, { data: [], meta: { totalPages: 0 } })

    client.ensure_score_config(name: "mood", data_type: "CATEGORICAL", categories: [{ label: "declarative", value: 0 }])

    expect(calls.last).to include(method: :post, url: "http://lf.test:3000/api/public/score-configs")
    expect(calls.last[:body]).to include("name" => "mood", "dataType" => "CATEGORICAL")
  end

  it "walks every page of a listing" do
    reply(200, { data: [{ name: "a" }], meta: { totalPages: 2 } })
    reply(200, { data: [{ name: "b" }], meta: { totalPages: 2 } })

    expect(client.list_score_configs.map { |c| c["name"] }).to eq(%w[a b])
  end

  it "lists the items of one dataset by name" do
    reply(200, { data: [{ id: "nd-1" }], meta: { totalPages: 1 } })

    expect(client.list_dataset_items(dataset: "sfl narrative").map { |i| i["id"] }).to eq(["nd-1"])
    expect(calls.first[:url]).to include("datasetName=sfl+narrative&page=1")
  end

  it "posts a dataset run item linking an item to a trace" do
    client.create_run_item(run_name: "r1", dataset_item_id: "nd-1", trace_id: "t1")

    expect(calls.first[:body]).to include("runName" => "r1", "datasetItemId" => "nd-1", "traceId" => "t1")
  end

  it "raises a typed error carrying status and body on a non-2xx reply" do
    reply(401, { message: "bad key" })

    expect { client.list_datasets }.to raise_error(described_class::Error, /401.*bad key/)
  end

  it "wraps transport failures in the same error type" do
    failing = -> (*) { raise Errno::ECONNREFUSED }
    unreachable = described_class.new(host: "http://x", public_key: "p", secret_key: "s", transport: failing)

    expect { unreachable.list_datasets }.to raise_error(described_class::Error, /unreachable/)
  end

  describe "logging" do
    let(:logger) { instance_spy(SFL::Core::Ports::JournaldLogger) }
    let(:client) do
      described_class.new(host: "http://lf.test:3000", public_key: "pk-secret-1", secret_key: "sk-secret-2",
        transport:, logger:)
    end

    it "logs one debug line per request with method, path, status and latency_ms" do
      client.upsert_dataset(name: "ds")

      expect(logger).to have_received(:debug).with(
        a_kind_of(String), method: "POST", path: "/api/public/v2/datasets", status: 200, latency_ms: a_kind_of(Numeric)
      )
    end

    it "warns on a non-2xx response and still raises" do
      reply(500, { "message" => "boom" })

      expect { client.list_datasets }.to raise_error(described_class::Error)
      expect(logger).to have_received(:warn).with(a_kind_of(String), hash_including(status: 500))
    end

    it "logs an error on transport failure" do
      failing = -> (*) { raise Errno::ECONNREFUSED }
      failing_client = described_class.new(host: "http://lf.test", public_key: "pk", secret_key: "sk",
        transport: failing, logger:)

      expect { failing_client.list_datasets }.to raise_error(described_class::Error, /unreachable/)
      expect(logger).to have_received(:error).with(
        a_kind_of(String), hash_including(method: "GET", error_class: Errno::ECONNREFUSED)
      )
    end

    it "never puts headers, keys or bodies in any logged field or message" do
      secret = "TOP-SECRET-BODY-VALUE"
      captured = []
      capture = Object.new
      %i[debug info warn error fatal].each do |level|
        capture.define_singleton_method(level) { |message = nil, **fields| captured << [message, fields] }
      end
      leaky = lambda do |_method, _url, _headers, _body|
        SFL::Eval::LangfuseClient::Response.new(500, JSON.generate({ "error" => secret }))
      end
      subject_client = described_class.new(host: "http://lf.test", public_key: "pk-secret-1",
        secret_key: "sk-secret-2", transport: leaky, logger: capture)

      expect { subject_client.create_score(name: "n", value: 1, comment: secret) }
        .to raise_error(described_class::Error)

      rendered = captured.flatten.join(" ")
      [secret, "pk-secret-1", "sk-secret-2", "Authorization", "Basic ", Base64.strict_encode64("pk-secret-1:sk-secret-2")]
        .each { |forbidden| expect(rendered).not_to include(forbidden) }
      expect(captured).not_to be_empty
    end
  end
end
