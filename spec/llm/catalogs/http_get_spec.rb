# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::LLM::Catalogs::HttpGet do
  let(:http) { instance_double(Net::HTTP) }

  def reply(klass, code, body)
    klass.new("1.1", code, "msg").tap { |response| allow(response).to receive(:body).and_return(body) }
  end

  before { allow(Net::HTTP).to receive(:start).and_yield(http) }

  it "returns the body of a 2xx reply, sending the headers" do
    allow(http).to receive(:get).with("/api/v1/models?x=1", { "A" => "b" }).and_return(reply(Net::HTTPOK, "200", "{}"))

    expect(described_class.new(timeout: 3).call("https://openrouter.ai/api/v1/models?x=1", { "A" => "b" })).to eq("{}")
    expect(Net::HTTP).to have_received(:start)
      .with("openrouter.ai", 443, use_ssl: true, open_timeout: 3, read_timeout: 3)
  end

  it "raises LLM::Error naming the status for any other reply" do
    allow(http).to receive(:get).and_return(reply(Net::HTTPServiceUnavailable, "503", ""))

    expect { described_class.new.call("http://tinybot:11434/api/tags") }
      .to raise_error(SFL::LLM::Error, "GET http://tinybot:11434/api/tags returned 503")
  end
end
