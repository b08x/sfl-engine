This guide explains how to configure the SFL Engine environment, from essential database connections to advanced LLM provider settings. The configuration system uses a single composition root in `lib/sfl/boot.rb` [lib/sfl/boot.rb](lib/sfl/boot.rb#L1-L261) that reads all environment variables at startup and injects dependencies throughout the application. This approach ensures that configuration is centralized, testable, and predictable.

## Configuration Architecture

The environment configuration follows a layered architecture that separates infrastructure concerns from application logic. The boot process loads configuration from three sources in this order: shell environment variables, the `.env` file, and application-specific defaults.

```mermaid
flowchart TD
    A[Startup] --> B{Load .env?}
    B -->|Yes| C[Read .env file]
    B -->|No| D[Use shell ENV]
    C --> D
    D --> E[Build LLM Config]
    D --> F[Build Database Config]
    D --> G[Build API Config]
    D --> H[Build Python Config]
    E --> I[Validate API Keys]
    I --> J[Initialize Providers]
    J --> K[Application Ready]
    
    E --> L[Pass 2 Annotation]
    E --> M[Pass 2 Batch Annotation]
    E --> N[Context Synthesis]
    E --> O[Embedding]
    E --> P[Ingest Classification]
    E --> Q[Loader Drafting]
    
    style A fill:#e1f5ff
    style K fill:#c8e6c9
```

The configuration system uses **dependency injection** throughout the codebase. Classes never read `ENV` directly—instead, they receive configuration through constructor arguments from the composition root in `SFL::Boot.call` [lib/sfl/boot.rb](lib/sfl/boot.rb#L46-L87). This design makes the application testable and ensures consistent behavior across environments.

## Quick Setup Options

You have two primary options for configuring your environment: the interactive setup wizard or manual configuration. For most developers, the interactive wizard is the fastest path to a working setup.

### Option 1: Interactive Setup Wizard

Run the setup script from your project root:

```bash
bundle exec bin/setup-config
```

The wizard walks you through every required environment variable, offering sensible defaults and preserving any existing `.env` values [bin/setup-config](bin/setup-config#L1-L204). It only manages variables that the current codebase actually reads—legacy variables like `DSPY_PROVIDER`, `VISION_MODEL`, or `LOG_LEVEL` are left untouched if present in your existing `.env` file.

### Option 2: Manual Configuration

Create a `.env` file in your project root based on the `.env.example` template:

```bash
cp .env.example .env
# Edit .env with your settings
```

The example file shows the minimal recommended configuration [`.env.example`](.env.example#L1-L9), but you'll typically need to add additional values based on your chosen LLM providers.

## Environment Variable Categories

Configuration variables are grouped by functional area. Understanding these categories helps you troubleshoot issues and optimize your setup for different use cases.

### Database Configuration

The database connection is the most critical piece of infrastructure. SFL Engine requires a PostgreSQL database with the `pgvector` extension for vector embeddings and `pg_trgm` for trigram-based text search.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `DATABASE_URL` | Yes | None | PostgreSQL connection string in format `postgresql://user:password@host:port/database` |

The application expects two databases: a development database (`sfl_engine_dev`) and a test database (`sfl_engine_v2_test`). The Docker Compose configuration automatically creates the test database on first initialization using the init script [docker/init-test-db.sql](docker/init-test-db.sql#L1-L7).

### Environment Mode

The environment mode determines behavior for development tools and error handling.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `RACK_ENV` | No | `development` | Application environment: `development`, `production`, or `test` |
| `SESSION_SECRET` | No | Dev-only key | Secret key for session encryption (must be set in production) |

In development mode, the application enables debugging tools and automatic model annotations for Sequel models [boot.rb](boot.rb#L25-L32).

### LLM Provider Configuration

LLM configuration is task-specific, allowing different models for different operations. Each task can be independently configured with provider, model, and optional parameters.

**Required API Keys by Provider:**

| Provider | API Key Variable | Notes |
|----------|------------------|-------|
| OpenRouter | `OPENROUTER_API_KEY` | Default provider for Pass 2 tasks |
| Anthropic | `ANTHROPIC_API_KEY` | Recommended for quality annotations |
| OpenAI | `OPENAI_API_KEY` | Requires base URI configuration for non-standard endpoints |
| Google Gemini | `GOOGLE_API_KEY` | For Gemini models |
| Mistral | `MISTRAL_API_KEY` | For Mistral models |
| Ollama | None | Self-hosted, no API key required |

**Per-Task Configuration:**

All task configuration variables follow the pattern `SFL_TASK_<TASK_NAME>_<PARAMETER>`. The six supported tasks are:

1. **pass_two_annotation** - Clause-level annotation with LLM
2. **pass_two_batch_annotation** - Bulk annotation operations
3. **context_synthesis** - Context window synthesis
4. **embedding** - Vector embedding generation
5. **ingest_classification** - Document classification during ingest
6. **loader_drafting** - Content loader drafting

**Configuration Pattern:**

```
SFL_TASK_<TASK_NAME>_PROVIDER=provider_name
SFL_TASK_<TASK_NAME>_MODEL=model_id
SFL_TASK_<TASK_NAME>_TEMPERATURE=0.0-1.0  # Optional
```

**Default Behavior:**

- Pass 2 tasks default to OpenRouter provider [lib/sfl/boot.rb](lib/sfl/boot.rb#L23)
- Embedding defaults to Ollama provider [lib/sfl/boot.rb](lib/sfl/boot.rb#L27)
- Context synthesis borrows from pass_two_annotation configuration [lib/sfl/boot.rb](lib/sfl/boot.rb#L94-L98)
- Ingest classification borrows from embedding configuration [lib/sfl/boot.rb](lib/sfl/boot.rb#L103-L107)
- Loader drafting borrows from pass_two_annotation configuration [lib/sfl/boot.rb](lib/sfl/boot.rb#L109-L113)

### Ollama Configuration

For self-hosted LLM operations via Ollama, configure the base URL and embedding model.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `OLLAMA_BASE_URL` | No | `http://tinybot:11434` | Ollama API endpoint URL |
| `EMBEDDING_MODEL` | No | `embeddinggemma:latest` | Default embedding model name |

The Docker Compose configuration assumes an Ollama instance at `http://tinybot:11434` [lib/sfl/boot.rb](lib/sfl/boot.rb#L33).

### spaCy and Python Configuration

Pass 1 syntactic parsing runs as a Python subprocess. These variables control Python provisioning and spaCy model selection.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SPACY_MODEL` | No | `en_core_web_sm` | spaCy model for syntactic parsing |
| `SFL_PYTHON_VERSION` | No | `3.12` | Python version for vendored environment |
| `SFL_SPACY_REQUIREMENT` | No | `spacy` | spaCy package requirement spec |
| `SFL_EMBEDDING_TIMEOUT_SECONDS` | No | `30.0` | Timeout for embedding operations |

The vendored Python environment is provisioned by `bin/setup-python` into `.sfl-python/` directory [bin/setup-python](bin/setup-python#L1-L133). This isolation prevents conflicts with system Python packages and ensures reproducible builds across different host environments.

### API Server Configuration

These variables control the HTTP API server behavior when running via `bundle exec sfl-api` or Docker Compose.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `HOST` | No | `0.0.0.0` | Bind address for the API server |
| `PORT` | No | `3001` | Port number for the API server |
| `SFL_API_CORS_ORIGINS` | No | Empty | Comma-separated list of allowed CORS origins |
| `SFL_API_DEBUG_ERRORS` | No | `false` | Show detailed error responses |

The API server defaults to `0.0.0.0` to be reachable from other containers on the same Docker network [exe/sfl-api](exe/sfl-api#L1-L21). Set `HOST=localhost` explicitly for bare-metal-only setups that don't need external connectivity.

### Langfuse Tracing Configuration

Optional Langfuse integration provides observability for LLM operations.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `LANGFUSE_HOST` | No | None | Langfuse server hostname |
| `LANGFUSE_PUBLIC_KEY` | No | None | Langfuse project public key |
| `LANGFUSE_SECRET_KEY` | No | None | Langfuse project secret key |
| `SFL_ENABLE_TRACING` | No | `false` | Enable Langfuse tracing at boot |
| `SFL_SKIP_LLM_BOOT` | No | `false` | Skip LLM initialization |

When tracing is requested, the boot process performs a reachability check before proceeding [lib/sfl/boot.rb](lib/sfl/boot.rb#L222-L234). This prevents silent failures when the Langfuse endpoint is unreachable.

### Docker Services Configuration

These variables control automatic Docker service startup behavior.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SFL_AUTO_START_DOCKER` | No | `false` | Automatically start Docker Compose services |

When enabled, the application automatically starts PostgreSQL and Redis services via Docker Compose before initializing the database connection [lib/sfl/docker_services.rb](lib/sfl/docker_services.rb#L1-L52). This is particularly useful for development workflows but should not be used when connecting to external database instances.

### Development and Debugging Flags

These variables control development-specific behavior.

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `SFL_FORCE_PYTHON_VENDOR` | No | `false` | Force reinstall of Python dependencies |

Setting `SFL_FORCE_PYTHON_VENDOR=1` forces `bin/setup-python` to reinstall the vendored Python environment even if the marker file indicates it's already installed [bin/setup-python](bin/setup-python#L126-L133).

## Configuration Loading Process

The configuration loading process happens in a specific order that determines which values take precedence when multiple sources are present.

```mermaid
sequenceDiagram
    participant App as Application Boot
    participant Dotenv as Dotenv.load()
    participant ENV as ENV Hash
    participant Config as Config.get()
    participant Boot as SFL::Boot.call()
    
    App->>Dotenv: Load .env file if not production
    Dotenv->>ENV: Merge .env values into ENV hash
    Config->>ENV: Read DATABASE_URL, SESSION_SECRET
    Config->>Config: Return configuration object
    Boot->>ENV: Read all task-specific variables
    Boot->>Boot: Build per-task LLM config
    Boot->>Boot: Validate API keys
    Boot->>Boot: Initialize all providers
    Boot->>Boot: Return Boot::Result
```

The boot sequence in `boot.rb` demonstrates this process [boot.rb](boot.rb#L1-L63):

1. Load `.env` file (unless in production mode)
2. Initialize Zeitwerk autoloader for `app/` directory
3. Ensure Docker services are running if configured
4. Connect to database via `Providers::DB::Conn.boot`
5. Call `SFL::Boot.call` with optional feature flags
6. Initialize mailer, logger, and engine providers

## Docker Compose Environment Variables

The Docker Compose configuration includes service-specific environment variables that differ from bare-metal setups.

**Service-Level Configuration in docker-compose.yml:**

PostgreSQL service uses fixed credentials internally [docker-compose.yml](docker-compose.yml#L6-L10):

```yaml
POSTGRES_USER: sfl
POSTGRES_PASSWORD: sfl
POSTGRES_DB: sfl_engine_dev
```

The API service uses service DNS names rather than host ports [docker-compose.yml](docker-compose.yml#L47-L50):

```yaml
DATABASE_URL: postgresql://sfl:sfl@postgres:5432/sfl_engine_dev
HOST: "0.0.0.0"
PORT: "3001"
SFL_AUTO_START_DOCKER: "0"
```

The `SFL_AUTO_START_DOCKER="0"` setting prevents the containerized API from attempting to start Docker Compose services (which would cause a recursion loop since Compose already manages startup ordering via `depends_on`).

## Port Conflict Avoidance

The Docker Compose configuration uses non-standard ports to avoid conflicts with system services that may already be running on your development machine.

| Service | Standard Port | SFL Engine Port | Rationale |
|---------|---------------|-----------------|-----------|
| PostgreSQL | 5432 | 5433 (host) → 5432 (container) | Avoid conflict with system Postgres |
| Redis | 6379 | 6380 (host) → 6379 (container) | Avoid conflict with system Redis |
| API Server | None | 3001 | Free port for application API |

When running bare-metal (without Docker), you'll use these standard ports directly in your `DATABASE_URL` and other connection strings.

## Common Configuration Scenarios

### Local Development with Docker Compose

The recommended development setup uses Docker Compose for infrastructure dependencies:

```bash
# Start infrastructure services
docker compose up -d postgres redis

# Set DATABASE_URL to match docker-compose.yml
export DATABASE_URL="postgresql://sfl:sfl@localhost:5433/sfl_engine_dev"

# Configure your LLM provider
export OPENROUTER_API_KEY="your-key-here"
export SFL_TASK_PASS_TWO_ANNOTATION_MODEL="anthropic/claude-haiku-4.5"

# Run the application
bundle exec sfl-api
```

### Production Deployment

For production, you'll need to explicitly set all security-sensitive variables:

```bash
export RACK_ENV="production"
export SESSION_SECRET="$(openssl rand -base64 64)"
export DATABASE_URL="postgresql://user:pass@prod-db.example.com:5432/sfl_engine"
export OPENROUTER_API_KEY="your-production-key"
# ... other provider keys
```

Never use the development session secret or default values in production environments [app/config/config.rb](app/config/config.rb#L5-L6).

### Pass 1-Only Mode (No LLM)

You can run the system without any LLM provider for syntactic parsing only:

```bash
export SFL_SKIP_LLM_BOOT="true"
bundle exec exe/sfl-analyze --input document.txt --output analysis.json
```

This is useful for testing the Pass 1 pipeline or when you only need syntactic analysis without semantic annotation.

## Configuration Validation

The boot process validates configuration before initializing any services. Failed validations raise explicit errors that identify exactly what's missing.

**Validation Checks Performed:**

1. `DATABASE_URL` must be present and non-empty [lib/sfl/boot.rb](lib/sfl/boot.rb#L245-L250)
2. All configured provider API keys must be present and non-empty [lib/sfl/boot.rb](lib/sfl/boot.rb#L144-L152)
3. Database connection must succeed with the provided URL [lib/sfl/boot.rb](lib/sfl/boot.rb#L251-L254)
4. Langfuse endpoint must be reachable (if tracing is enabled) [lib/sfl/boot.rb](lib/sfl/boot.rb#L222-L234)

When validation fails, the error message explicitly states which variable or connection is problematic, making troubleshooting straightforward.

## Environment Variable Reference

### Core Infrastructure

```bash
# Required for all deployments
DATABASE_URL=postgresql://user:password@host:port/database

# Environment mode (development/production/test)
RACK_ENV=development

# Session security (production only)
SESSION_SECRET=your-random-secret-key
```

### LLM Providers

```bash
# OpenRouter (default for Pass 2)
OPENROUTER_API_KEY=sk-or-...
SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER=openrouter
SFL_TASK_PASS_TWO_ANNOTATION_MODEL=mistralai/mistral-small-3.2-24b-instruct

# Anthropic
ANTHROPIC_API_KEY=sk-ant-...
SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER=anthropic
SFL_TASK_PASS_TWO_ANNOTATION_MODEL=claude-haiku-4-5-20251001

# OpenAI
OPENAI_API_KEY=sk-...
OPENAI_BASE_URI=https://api.openai.com/v1  # Optional custom endpoint
SFL_TASK_PASS_TWO_ANNOTATION_PROVIDER=openai
SFL_TASK_PASS_TWO_ANNOTATION_MODEL=gpt-5.4-mini
```

### Ollama (Self-Hosted)

```bash
OLLAMA_BASE_URL=http://localhost:11434
SFL_TASK_EMBEDDING_PROVIDER=ollama
SFL_TASK_EMBEDDING_MODEL=embeddinggemma:latest
```

### spaCy Configuration

```bash
SPACY_MODEL=en_core_web_sm
SFL_PYTHON_VERSION=3.12
SFL_SPACY_REQUIREMENT=spacy
```

### API Server

```bash
HOST=0.0.0.0
PORT=3001
SFL_API_CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000
SFL_API_DEBUG_ERRORS=true  # Development only
```

### Langfuse Tracing

```bash
SFL_ENABLE_TRACING=true
LANGFUSE_HOST=https://cloud.langfuse.com
LANGFUSE_PUBLIC_KEY=pk-...
LANGFUSE_SECRET_KEY=sk-...
```

### Docker Integration

```bash
SFL_AUTO_START_DOCKER=1  # Automatically start postgres/redis via Compose
```

### Debugging

```bash
SFL_FORCE_PYTHON_VENDOR=1  # Reinstall Python dependencies
SFL_SKIP_LLM_BOOT=1  # Disable LLM initialization
```

## Next Steps

After configuring your environment, proceed with these setup steps:

1. **[Docker Compose Setup](3-docker-compose-setup)** - Configure Docker-based infrastructure services for development
2. **[Python Sidecar Setup](5-python-sidecar-setup)** - Provision the vendored Python environment for Pass 1 parsing
3. **[Quick Start](2-quick-start)** - Run your first analysis and verify the installation

The environment configuration is the foundation for all other setup steps. Once your `.env` file is correctly configured and dependencies are installed, you'll have a fully functional SFL Engine development environment.