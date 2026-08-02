# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::DockerServices do
  describe ".ensure_running!" do
    it "returns false and never shells out when SFL_AUTO_START_DOCKER isn't set to \"1\" (issue #17: " \
      "both call sites run before Boot.call's Dotenv.load, so ENV here never reflects .env's own " \
      "DATABASE_URL -- explicit opt-in, not URL-sniffing, is the only ordering-safe gate)" do
      calls = []
      command = -> (*args, **opts) { calls << [args, opts] and true }

      result = described_class.ensure_running!(env: {}, command:)

      expect(result).to be false
      expect(calls).to be_empty
    end

    it "treats SFL_AUTO_START_DOCKER=true (not the literal \"1\") as still opted out" do
      calls = []
      command = -> (*args, **opts) { calls << [args, opts] and true }

      result = described_class.ensure_running!(env: { "SFL_AUTO_START_DOCKER" => "true" }, command:)

      expect(result).to be false
      expect(calls).to be_empty
    end

    it "returns false and never shells out when docker-compose.yml doesn't exist" do
      calls = []
      command = -> (*args, **opts) { calls << [args, opts] and true }
      file_exists = -> (_path) { false }

      result = described_class.ensure_running!(env: { "SFL_AUTO_START_DOCKER" => "1" }, file_exists:, command:)

      expect(result).to be false
      expect(calls).to be_empty
    end

    it "returns false and never attempts `up` when `docker compose version` fails " \
      "(Docker not installed — a silent no-op, not an error)" do
      file_exists = -> (_path) { true }
      calls = []
      command = lambda do |*args, **opts|
        calls << [args, opts]
        !args.include?("version")
      end

      result = described_class.ensure_running!(env: { "SFL_AUTO_START_DOCKER" => "1" }, file_exists:, command:)

      expect(result).to be false
      expect(calls.size).to eq(1)
    end

    it "returns false without attempting `up` when the daemon is stopped (issue #18: `docker compose " \
      "version` alone succeeds even with the daemon down; `docker info` is the real reachability probe)" do
      file_exists = -> (_path) { true }
      calls = []
      command = lambda do |*args, **opts|
        calls << [args, opts]
        !args.include?("info")
      end

      result = described_class.ensure_running!(env: { "SFL_AUTO_START_DOCKER" => "1" }, file_exists:, command:)

      expect(result).to be false
      expect(calls.map(&:first)).to eq([%w[docker compose version], %w[docker info]])
    end

    it "returns false instead of raising when the command runner itself fails to spawn (issue #18)" do
      file_exists = -> (_path) { true }
      command = lambda do |*args, **_opts|
        raise Errno::ENOENT, "docker" if args.include?("up")

        true
      end

      result = nil
      expect do
        result = described_class.ensure_running!(env: { "SFL_AUTO_START_DOCKER" => "1" }, file_exists:, command:)
      end.not_to raise_error
      expect(result).to be false
    end

    it "runs `docker compose -f <file> up -d --wait` when opted in, the compose file exists, " \
      "and both the plugin and daemon are available" do
      file_exists = -> (_path) { true }
      calls = []
      command = lambda do |*args, **opts|
        calls << [args, opts]
        true
      end

      result = described_class.ensure_running!(
        env: { "SFL_AUTO_START_DOCKER" => "1" }, compose_file: "/tmp/compose.yml", file_exists:, command:
      )

      expect(result).to be true
      expect(calls.last.first).to eq(["docker", "compose", "-f", "/tmp/compose.yml", "up", "-d", "--wait"])
    end
  end
end
