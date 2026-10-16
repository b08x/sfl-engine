# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Boot, ".langfuse_client" do
  it "builds a client from LANGFUSE_BASE_URL when LANGFUSE_HOST is unset" do
    env = { "LANGFUSE_BASE_URL" => "http://lf.test", "LANGFUSE_PUBLIC_KEY" => "pk", "LANGFUSE_SECRET_KEY" => "sk" }

    expect(described_class.langfuse_client(env:, load_dotenv: false)).to be_a(SFL::Eval::LangfuseClient)
  end

  it "names every missing variable" do
    expect { described_class.langfuse_client(env: { "LANGFUSE_HOST" => "http://x" }, load_dotenv: false) }
      .to raise_error(SFL::Boot::Error, /LANGFUSE_PUBLIC_KEY, LANGFUSE_SECRET_KEY/)
  end
end
