# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::Tracing do
  let(:exporter) { instance_double(OpenTelemetry::Exporter::OTLP::Exporter) }
  let(:exporter_class) { class_double(OpenTelemetry::Exporter::OTLP::Exporter, new: exporter) }

  let(:span_processor) { instance_double(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor) }
  let(:span_processor_class) do
    class_double(OpenTelemetry::SDK::Trace::Export::BatchSpanProcessor, new: span_processor)
  end

  let(:sdk_config) { instance_double(OpenTelemetry::SDK::Configurator, use: nil, add_span_processor: nil) }
  let(:sdk) { class_double(OpenTelemetry::SDK) }

  before do
    described_class.instance_variable_set(:@configured, nil)
    allow(sdk).to receive(:configure).and_yield(sdk_config)
  end

  after { described_class.instance_variable_set(:@configured, nil) }

  it "builds the OTLP exporter pointed at Langfuse's OTel ingestion path with Basic auth" do
    described_class.configure(host: "https://cloud.langfuse.com", public_key: "pk", secret_key: "sk", sdk:,
      exporter_class:, span_processor_class:)

    expect(exporter_class).to have_received(:new).with(
      endpoint: "https://cloud.langfuse.com/api/public/otel",
      headers: { "Authorization" => "Basic #{Base64.strict_encode64('pk:sk')}" }
    )
  end

  it "registers the RubyLLM instrumentation and a span processor wrapping the exporter" do
    described_class.configure(host: "https://cloud.langfuse.com", public_key: "pk", secret_key: "sk", sdk:,
      exporter_class:, span_processor_class:)

    expect(sdk_config).to have_received(:use).with("OpenTelemetry::Instrumentation::RubyLLM")
    expect(span_processor_class).to have_received(:new).with(exporter)
    expect(sdk_config).to have_received(:add_span_processor).with(span_processor)
  end

  it "returns true and marks itself configured on the first call" do
    result = described_class.configure(host: "h", public_key: "pk", secret_key: "sk", sdk:, exporter_class:,
      span_processor_class:)

    expect(result).to be(true)
    expect(described_class).to be_configured
  end

  it "is a no-op returning false on a second call, never re-invoking the SDK" do
    described_class.configure(host: "h", public_key: "pk", secret_key: "sk", sdk:, exporter_class:,
      span_processor_class:)

    result = described_class.configure(host: "h", public_key: "pk", secret_key: "sk", sdk:, exporter_class:,
      span_processor_class:)

    expect(result).to be(false)
    expect(sdk).to have_received(:configure).once
  end
end
