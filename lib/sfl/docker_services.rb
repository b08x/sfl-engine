# frozen_string_literal: true

module SFL
  # Best-effort docker-compose auto-start for docker-compose.yml's
  # Postgres/Redis services, called from exe/sfl-analyze and config.ru
  # before Boot.call needs a real DB connection. Never raises — if Docker
  # isn't installed/running, or the compose file is missing, this is a
  # silent no-op and Boot's own DATABASE_URL connection error surfaces
  # normally; nothing in this codebase requires Docker specifically
  # (DATABASE_URL can point at any reachable Postgres).
  #
  # Explicit opt-in only (issue #17), not "inspect the effective
  # DATABASE_URL and skip for external ones" — both call sites invoke this
  # BEFORE Boot.call's Dotenv.load runs, so at this point ENV reflects only
  # the shell's own environment, not .env. Peeking at ENV["DATABASE_URL"]
  # here would silently miss every DATABASE_URL an operator sets in .env
  # (this repo's own documented, expected way to configure it), which is
  # worse than the bug this fixes. SFL_AUTO_START_DOCKER=1 sidesteps the
  # ordering problem entirely instead of trying to solve it.
  module DockerServices
    COMPOSE_FILE = File.expand_path("../../docker-compose.yml", __dir__)

    # @param compose_file [String] injectable for specs
    # @param env [#[]] injectable seam so specs never touch the real ENV
    # @param file_exists [#call] injectable seam so specs never touch the real filesystem
    # @param command [#call] injectable seam so specs never shell out (Kernel#system-compatible)
    # @return [Boolean] whether `docker compose up` was actually attempted
    module_function def ensure_running!(
      compose_file: COMPOSE_FILE,
      env: ENV,
      file_exists: File.method(:exist?),
      command: Kernel.method(:system)
    )
      return false unless env["SFL_AUTO_START_DOCKER"] == "1"
      return false unless file_exists.call(compose_file)
      return false unless command.call("docker", "compose", "version", out: File::NULL, err: File::NULL)
      # `docker compose version` only checks the Compose plugin is installed — it succeeds even
      # with the daemon stopped. `docker info` is the actual daemon-reachability probe (#18);
      # without it, the `up` below runs anyway, prints Docker's own error to the terminal, and
      # breaks the documented "Docker isn't running => silent no-op" contract.
      return false unless command.call("docker", "info", out: File::NULL, err: File::NULL)

      command.call("docker", "compose", "-f", compose_file, "up", "-d", "--wait")
    rescue SystemCallError
      # A spawn failure (e.g. the `docker` binary vanishing between the version/info probes and
      # `up`) is exactly the same "Docker isn't usable right now" case the guards above already
      # treat as a no-op, not a crash-the-caller condition (#18).
      false
    end
  end
end
