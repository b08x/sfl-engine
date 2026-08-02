# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::DockerServices do
  describe ".ensure_running!" do
    it "returns false and never shells out when docker-compose.yml doesn't exist" do
      command = instance_double(Method)
      file_exists = -> (_path) { false }

      result = described_class.ensure_running!(file_exists:, command:)

      expect(result).to be false
    end

    it "returns false and never attempts `up` when `docker compose version` fails " \
      "(Docker not installed/running — a silent no-op, not an error)" do
      file_exists = -> (_path) { true }
      calls = []
      command = lambda do |*args, **opts|
        calls << [args, opts]
        !args.include?("version")
      end

      result = described_class.ensure_running!(file_exists:, command:)

      expect(result).to be false
      expect(calls.size).to eq(1)
    end

    it "runs `docker compose -f <file> up -d --wait` when the compose file exists and docker is available" do
      file_exists = -> (_path) { true }
      calls = []
      command = lambda do |*args, **opts|
        calls << [args, opts]
        true
      end

      result = described_class.ensure_running!(compose_file: "/tmp/compose.yml", file_exists:, command:)

      expect(result).to be true
      expect(calls.last.first).to eq(["docker", "compose", "-f", "/tmp/compose.yml", "up", "-d", "--wait"])
    end
  end
end
