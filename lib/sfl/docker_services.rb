# frozen_string_literal: true

module SFL
  # Best-effort docker-compose auto-start for docker-compose.yml's
  # Postgres/Redis services, called from exe/sfl-analyze and config.ru
  # before Boot.call needs a real DB connection. Never raises — if Docker
  # isn't installed/running, or the compose file is missing, this is a
  # silent no-op and Boot's own DATABASE_URL connection error surfaces
  # normally; nothing in this codebase requires Docker specifically
  # (DATABASE_URL can point at any reachable Postgres).
  module DockerServices
    COMPOSE_FILE = File.expand_path("../../docker-compose.yml", __dir__)

    # @param compose_file [String] injectable for specs
    # @param file_exists [#call] injectable seam so specs never touch the real filesystem
    # @param command [#call] injectable seam so specs never shell out (Kernel#system-compatible)
    # @return [Boolean] whether `docker compose up` was actually attempted
    module_function def ensure_running!(
      compose_file: COMPOSE_FILE,
      file_exists: File.method(:exist?),
      command: Kernel.method(:system)
    )
      return false unless file_exists.call(compose_file)
      return false unless command.call("docker", "compose", "version", out: File::NULL, err: File::NULL)

      command.call("docker", "compose", "-f", compose_file, "up", "-d", "--wait")
    end
  end
end
