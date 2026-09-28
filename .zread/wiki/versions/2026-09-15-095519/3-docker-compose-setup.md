This guide explains how to set up and run SFL Engine using Docker Compose. Docker Compose manages the project's infrastructure services—Postgres for data storage and Redis for caching—and optionally runs the API server in a containerized environment. This approach isolates dependencies, provides consistent development environments, and simplifies onboarding for new developers.

Sources: [docker-compose.yml](docker-compose.yml#L1-L104), [README.md](README.md#L113-L157)

## Understanding the Architecture

SFL Engine's Docker Compose configuration follows a multi-service architecture with distinct responsibilities. The infrastructure layer (Postgres and Redis) runs by default, while application services (API and migration) are opt-in through profiles. This separation ensures bare-metal development remains the primary workflow while supporting containerized deployment when needed.

```mermaid
graph TB
    subgraph "Developer Machine"
        CLI["CLI exe/sfl-analyze"]
        BARE["Bare Metal<br/>bundle exec exe/sfl-api"]
    end
    
    subgraph "Docker Compose Network"
        PG[(Postgres<br/>pgvector/pgvector:0.8.6-pg16<br/>Port: 5433→5432)]
        REDIS[(Redis<br/>redis/redis-stack:latest<br/>Port: 6380→6379)]
        
        subgraph "App Profile Optional"
            API["API Service<br/>docker/api.Dockerfile<br/>Port: 3001"]
            MIGRATE["Migration Service<br/>One-shot task"]
        end
    end
    
    CLI -->|"DATABASE_URL"| PG
    CLI -->|"CACHE"| REDIS
    BARE -->|"DATABASE_URL"| PG
    BARE -->|"CACHE"| REDIS
    
    API -->|"DATABASE_URL"| PG
    API -->|"CACHE"| REDIS
    MIGRATE -->|"DATABASE_URL"| PG
    
    style CLI fill:#e1f5fe
    style BARE fill:#e1f5fe
    style API fill:#fff3e0
    style MIGRATE fill:#fff3e0
```

The architecture emphasizes flexibility: services communicate within the Docker network using service names (like `postgres:5432`), while external access happens through remapped host ports (5433 for Postgres, 6380 for Redis) to avoid conflicts with system services. This design lets you run the CLI and bare-metal API against Docker-managed infrastructure without requiring containerization of the application itself.

Sources: [docker-compose.yml](docker-compose.yml#L1-L104), [lib/sfl/docker_services.rb](lib/sfl/docker_services.rb#L20-L49)

## Services Overview

The Docker Compose configuration defines four services with different roles and startup behaviors.

### Infrastructure Services

**Postgres Database** serves as the primary data store for clauses, embeddings, and annotation metadata. It uses the `pgvector/pgvector:0.8.6-pg16` image, which includes pgvector extension for vector similarity search operations. The service listens on host port 5433 (forwarded to container port 5432) to avoid conflicts with system Postgres instances. A named volume `sfl_engine_pgdata` persists database data across container restarts, and an initialization script automatically creates a separate test database `sfl_engine_v2_test` for the test suite.

Sources: [docker-compose.yml](docker-compose.yml#L2-L24), [docker/init-test-db.sql](docker/init-test-db.sql#L1-L7)

**Redis** provides caching and job queue capabilities using the `redis/redis-stack:latest` image. Like Postgres, it uses a non-default host port (6380) to avoid conflicts with local Redis instances. The service also exposes RedisInsight UI on port 8001, giving you a visual interface for exploring cached data. Persistent storage uses the `sfl_engine_redisdata` named volume, and health checks ensure the service is ready before dependent applications attempt connections.

Sources: [docker-compose.yml](docker-compose.yml#L26-L40)

### Application Services (App Profile)

**API Service** runs the HTTP API server in a containerized environment. Built from `docker/api.Dockerfile`, it includes Ruby 4.0.1, all gem dependencies, and spaCy for syntactic parsing—baked directly into the image rather than running as a separate sidecar container. This avoids the complexity of Docker-in-Docker setups. The service starts behind the `"app"` profile, meaning it only runs when explicitly requested with `--profile app`. It depends on healthy Postgres and Redis services and exposes the API on host port 3001. A health check verifies the `/health` endpoint responds correctly before marking the service as ready.

Sources: [docker-compose.yml](docker-compose.yml#L48-L79), [docker/api.Dockerfile](docker/api.Dockerfile#L1-L54)

**Migration Service** provides a one-shot task for running database migrations. Unlike many frameworks that auto-migrate on startup, SFL Engine requires explicit migration execution as a deliberate action. This service uses the same Dockerfile as the API but runs `bundle exec rake db:migrate` instead of starting a server. It also sits behind the `"app"` profile and requires a healthy Postgres connection before executing. Run this with `--rm` to ensure the container exits cleanly after migrations complete.

Sources: [docker-compose.yml](docker-compose.yml#L86-L99), [AGENTS.md](AGENTS.md#L77-L78)

| Service | Image | Host Port | Profile | Purpose |
|---------|-------|-----------|---------|---------|
| postgres | pgvector/pgvector:0.8.6-pg16 | 5433 → 5432 | None | Data storage with pgvector |
| redis | redis/redis-stack:latest | 6380 → 6379 | None | Caching and job queue |
| api | Built from docker/api.Dockerfile | 3001 → 3001 | app | HTTP API server |
| migrate | Built from docker/api.Dockerfile | - | app | One-shot database migrations |

Sources: [docker-compose.yml](docker-compose.yml#L1-L104)

## Prerequisites

Before using Docker Compose with SFL Engine, ensure you have the following tools installed:

- **Docker Engine** version 20.10 or later
- **Docker Compose** plugin (included with Docker Desktop or installable separately)
- **Git** for cloning the repository
- **Ruby** 4.0.1 and **Bundler** for bare-metal development (optional if running everything in containers)

Verify your Docker installation with:
```bash
docker --version
docker compose version
```

Docker must be running locally—the `SFL::DockerServices.ensure_running!` helper checks both the Compose plugin and Docker daemon availability before attempting service startup.

Sources: [lib/sfl/docker_services.rb](lib/sfl/docker_services.rb#L34-L41), [AGENTS.md](AGENTS.md#L31-L36)

## Quick Start Workflow

Getting started with Docker Compose follows a straightforward sequence that starts infrastructure services first, then optionally adds application services.

```mermaid
flowchart TD
    A[Clone Repository] --> B[Start Infrastructure Services]
    B --> C{Development Mode?}
    C -->|Bare Metal CLI| D[Setup Python Sidecar]
    D --> E[Configure Environment]
    E --> F[Run Migrations]
    F --> G[Use CLI or API]
    
    C -->|Containerized| H[Build API Image]
    H --> I[Run Migrations]
    I --> J[Start API Service]
    J --> K[Access API on Port 3001]
    
    style A fill:#e3f2fd
    style B fill:#e3f2fd
    style D fill:#fff3e0
    style E fill:#fff3e0
    style F fill:#fff3e0
    style G fill:#fff3e0
    style H fill:#e8f5e9
    style I fill:#e8f5e9
    style J fill:#e8f5e9
    style K fill:#e8f5e9
```

**Step 1: Clone and Navigate**
```bash
git clone <repository-url>
cd sfl-engine
```

**Step 2: Start Infrastructure Services**
```bash
docker compose up -d
```
This command starts Postgres (port 5433) and Redis (port 6380) in detached mode. Health checks ensure both services are ready before proceeding.

Sources: [docker-compose.yml](docker-compose.yml#L1-L41), [README.md](README.md#L115-L119)

**Step 3: Choose Your Development Mode**

For **bare-metal development** (recommended for most CLI usage):
```bash
bin/setup-config              # Interactive environment setup
bin/setup-python              # Vendor spaCy for Pass 1 parsing
bundle install                # Install Ruby dependencies
bundle exec rake db:migrate   # Run database migrations
```

This approach keeps your Ruby application running directly on your host while using Docker-managed Postgres and Redis. Configure your `.env` file with `DATABASE_URL=postgresql://sfl:sfl@127.0.0.1:5433/sfl_engine_dev` and `REDIS_URL=redis://127.0.0.1:6380`.

Sources: [README.md](README.md#L115-L122), [AGENTS.md](AGENTS.md#L31-L36)

For **containerized development** (running the API server inside Docker):
```bash
# Build the API image
docker compose --profile app build api

# Run migrations
docker compose --profile app run --rm migrate

# Start the API service
docker compose --profile app up -d api
```

The API service will be available at `http://127.0.0.1:3001`. Note that within the Docker network, the API connects to `postgres:5432` (not the remapped host port 5433) because services communicate using internal DNS names.

Sources: [README.md](README.md#L152-L157), [docker-compose.yml](docker-compose.yml#L61-L66)

## Configuration

### Environment Variables

Create a `.env` file in the project root using `.env.example` as a template. For Docker Compose usage:

```bash
# Database connection (bare metal - uses host port remapping)
DATABASE_URL=postgresql://sfl:sfl@127.0.0.1:5433/sfl_engine_dev

# Redis connection (bare metal - uses host port remapping)
REDIS_URL=redis://127.0.0.1:6380

# LLM provider configuration (shared across bare metal and containerized)
SFL_TASK_PASS_TWO_ANNOTATION_MODEL=openrouter/mistralai/mistral-small-3.2-24b-instruct
SFL_TASK_EMBEDDING_MODEL=ollama/embeddinggemma:latest
OPENROUTER_API_KEY=your_key_here
```

The containerized API service overrides `DATABASE_URL` internally to use the service name (`postgres:5432`) rather than the host remapped port. This happens automatically in `docker-compose.yml`, so you don't need to modify your `.env` when switching between bare-metal and containerized modes.

Sources: [docker-compose.yml](docker-compose.yml#L57-L62), [.env.example](.env.example#L1-L9), [AGENTS.md](AGENTS.md#L72-L73)

### Auto-Starting Docker Services

The application includes an optional Docker auto-start feature enabled by setting `SFL_AUTO_START_DOCKER=1` in your environment. When enabled, `SFL::DockerServices.ensure_running!` automatically starts the Postgres and Redis services via `docker compose up -d --wait` before the application attempts database connections. This feature checks for Docker availability, daemon reachability, and compose file existence before attempting startup—it silently falls back to no-op if Docker is unavailable.

This auto-start is **explicit opt-in only**. The code deliberately does not inspect your `DATABASE_URL` to skip Docker for external databases, because the environment check happens before `Dotenv.load` runs. Setting the environment variable ensures predictable behavior across different deployment scenarios.

Sources: [lib/sfl/docker_services.rb](lib/sfl/docker_services.rb#L20-L49), [AGENTS.md](AGENTS.md#L79-L80)

## Common Workflows

### Viewing Service Logs

Monitor infrastructure services:
```bash
docker compose logs -f postgres redis
```

View API service logs:
```bash
docker compose --profile app logs -f api
```

The `-f` flag follows logs in real-time, which is useful during development and debugging.

### Restarting Services

Restart infrastructure after configuration changes:
```bash
docker compose restart postgres redis
```

Restart the API service:
```bash
docker compose --profile app restart api
```

Use `restart` instead of `up` when you want to apply changes without recreating containers. For full rebuilds (like after modifying `Dockerfile`), use `docker compose up -d --build`.

### Stopping and Cleaning

Stop all running services:
```bash
docker compose down
```

Stop and remove volumes (warning: destroys all data):
```bash
docker compose down -v
```

Stop only application services, keep infrastructure running:
```bash
docker compose --profile app down
```

This is useful when switching between bare-metal and containerized API modes—you can stop the containerized API while keeping Postgres and Redis available for CLI usage.

### Accessing RedisInsight

RedisInsight provides a web-based UI for exploring your Redis data. After starting the Redis service, navigate to:

```
http://localhost:8001
```

This connects you to the Redis instance running in the container, letting you inspect cached values, monitor performance, and debug caching behavior.

Sources: [docker-compose.yml](docker-compose.yml#L26-L40)

## Troubleshooting

### Port Conflicts

If you see errors about ports 5433 or 6380 being in use, another process is already using those ports. This typically happens when:

- A previous Docker Compose instance is still running
- Another application is using those ports

Check what's listening:
```bash
lsof -i :5433
lsof -i :6380
```

Stop the conflicting process or modify the port mappings in `docker-compose.yml` to use different host ports.

### Docker Daemon Not Running

If Docker commands fail with "Cannot connect to the Docker daemon", start Docker Desktop or the Docker service:

```bash
# On Linux with systemd
sudo systemctl start docker
```

The `SFL::DockerServices.ensure_running!` helper explicitly checks for daemon reachability before attempting service startup to avoid confusing error messages.

Sources: [lib/sfl/docker_services.rb](lib/sfl/docker_services.rb#L36-L41)

### Database Connection Refused

If the application cannot connect to Postgres:

1. Verify the service is healthy:
   ```bash
   docker compose ps postgres
   ```

2. Check health status:
   ```bash
   docker compose exec postgres pg_isready -U sfl -d sfl_engine_dev
   ```

3. Ensure you're using the correct port (5433 for bare-metal connections, 5432 within the Docker network)

4. Verify the `.env` file `DATABASE_URL` matches your deployment mode

### Migration Failures

Migration errors typically indicate missing or outdated database schema. Ensure:

1. Postgres is healthy before running migrations
2. You're using the correct service command:
   ```bash
   docker compose --profile app run --rm migrate
   ```
3. No manual schema changes have been applied outside the migration system

Remember that migrations are never automatic—you must run them explicitly after database creation or schema changes.

Sources: [docker-compose.yml](docker-compose.yml#L86-L99), [AGENTS.md](AGENTS.md#L77-L78)

## Next Steps

With Docker Compose running and services configured, you're ready to explore SFL Engine's capabilities:

- **[Environment Configuration](4-environment-configuration)** — Learn about additional environment variables for LLM providers, API keys, and feature flags
- **[Python Sidecar Setup](5-python-sidecar-setup)** — Understand Pass 1 syntactic parsing and the spaCy integration for local development
- **[Quick Start](2-quick-start)** — Run your first analysis pipeline with the CLI or API
- **[CLI Usage](23-cli-usage)** — Explore the full command-line interface for analyzing conversations, documentation, and knowledge bases
- **[HTTP API Reference](24-http-api-reference)** — Interact with the containerized or bare-metal API endpoints