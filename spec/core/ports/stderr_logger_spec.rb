# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Ports::StderrLogger do
  subject(:logger) { described_class.new(level: Logger::DEBUG) }

  it_behaves_like "a logger port"

  it "appends structured fields as key=value pairs" do
    expect { logger.info("persisted", document_id: "doc-1", count: 3) }
      .to output("[INFO] persisted document_id=doc-1 count=3\n").to_stderr_from_any_process
  end

  it "leaves the message untouched when there are no fields" do
    expect { logger.warn("plain") }.to output("[WARN] plain\n").to_stderr_from_any_process
  end
end
