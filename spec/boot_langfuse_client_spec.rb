# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Boot, ".langfuse_client" do
  it "builds a client from LANGFUSE_BASE_URL when LANGFUSE_HOST is unset" do
    env = { "LANGFUSE_BASE_URL" => "http://lf.test", "LANGFUSE_PUBLIC_KEY" => "pk", "LANGFUSE_SECRET_KEY" => "sk" }

    expect(described_class.langfuse_client(env:, load_dotenv: false)).to be_a(SFL::Eval::LangfuseClient)
  end

  it "passes the configured logger to the client" do
    env = { "LANGFUSE_HOST" => "http://lf.test", "LANGFUSE_PUBLIC_KEY" => "pk", "LANGFUSE_SECRET_KEY" => "sk" }
    logger = instance_double(SFL::Core::Ports::StderrLogger)
    allow(described_class).to receive(:logger).and_return(logger)

    client = described_class.langfuse_client(env:, load_dotenv: false)

    expect(client.instance_variable_get(:@logger)).to be(logger)
  end

  it "names every missing variable" do
    expect { described_class.langfuse_client(env: { "LANGFUSE_HOST" => "http://x" }, load_dotenv: false) }
      .to raise_error(SFL::Boot::Error, /LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY/)
  end
end
