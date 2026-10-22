# frozen_string_literal: true

require "spec_helper"
require "json"
require "logger"
require "rack/test"
require "roda"

# Loads the Roda app without boot.rb: Config and the Providers it reads are
# stubbed, so no database, Docker, mail or LLM is needed. Each request below
# must be refused before the route reaches Providers::Engine.get.
RSpec.describe "Sfl rejects the pre-rename document_id parameter" do # rubocop:disable RSpec/DescribeClass -- Sfl is loaded inside the example group
  include Rack::Test::Methods

  before do
    stub_const("Config", Module.new do
      def self.get = { secret: "s" * 64 }
      def self.not_production? = false
    end)
    stub_const("Providers::Logger", Module.new { def self.get = Logger.new(File::NULL) })
    stub_const("Providers::Engine", Module.new do
      def self.get = raise("the request reached the engine")
      def self.cors_origins = []
      def self.debug_errors? = false
    end)
    require_relative "../../app/sfl"
  end

  def app = Sfl

  def error_of(response) = JSON.parse(response.body).fetch("error")

  it "lets a request without document_id through to the engine" do
    get "/clauses"

    expect(last_response.status).to eq(500)
  end

  %w[/clauses /graph/nodes /graph/edges].each do |path|
    it "returns 400 naming section_id for GET #{path}?document_id=" do
      get path, "document_id" => "doc-1"

      expect(last_response.status).to eq(400)
      expect(error_of(last_response)).to eq("document_id is no longer accepted; send section_id instead")
    end
  end

  it "returns 400 naming section_id for POST /pipeline/compile with document_id" do
    post "/pipeline/compile", JSON.dump("text" => "hello", "document_id" => "doc-1"),
      "CONTENT_TYPE" => "application/json"

    expect(last_response.status).to eq(400)
    expect(error_of(last_response)).to include("section_id")
  end
end
