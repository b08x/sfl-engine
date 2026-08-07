*Session Start: 2026-08-07*

# SIFT Protocol Report: Intelligent Ingest & Ohm/Redis Architecture

## Search Query Pre-Execution Bias Check
1. `sfl-engine codebase ingestion process` 
   - **Bias:** Presumes ingestion is a monolith. The recent architecture split divides it into Orchestrator (Redis) and Workers.
2. `sfl-engine router rack implementation` 
   - **Bias:** Assumes Rack middleware is the primary integration point, whereas the backlog explicitly targets Roda/Falcon (#36).
3. `sfl-engine postgres pgvector schema` 
   - **Bias:** Overlooks the ephemeral state layer. Postgres only tracks the finalized domain vectors, not the job state (which is now Ohm/Redis).
4. `ohm index querying performance`
   - **Bias:** Assumes 10,000 to 50,000 jobs will strain Redis indexing. Set intersection on 50K items in Redis is negligible; pre-optimizing here is a waste of time.

---

## 1. 📋 Identified Issues & Requirements Table

| Item | Type | Description & Context | Priority |
| :--- | :--- | :--- | :--- |
| **Boot.rb Wiring** | Architecture | `SFL::Boot.call` currently manages Postgres (`require_db: true`). It must be extended to support Redis (`require_redis: true`) to bootstrap the job queue. | 5 |
| **Ohm Model Struct** | Data Layer | The `IngestJob` class does not exist. It needs to be scaffolded with attributes and state indices to fulfill the queue contract. | 5 |
| **#51 & #52** | Architecture | `Ingest::Orchestrator` and CLI are currently disjointed. The CLI directory (`lib/sfl/cli/`) lacks the ingestion runner, only containing progress bars. | 5 |
| **Worker Entrypoint** | CLI/Tooling | There is no process to consume the queue. We need a `sfl-worker` executable or a `rake jobs:work` task that polls `IngestJob.find(state: "pending")`. | 4 |
| **#54 & #55** | Feature | Missing format parsers (HTML, Multimedia). Currently, only JSON and Markdown loaders exist in `lib/sfl/core/loaders/`. | 4 |
| **#36 & #41** | Scaffolding | Roda API layer is completely absent. The `exe/sfl-api` file exists but routes to an empty router. | 4 |
| **Connection Pooling**| Infrastructure | If Falcon/Roda spins up multiple threads, the standard `Redic` connection used by Ohm might need connection pooling (`connection_pool` gem). | 3 |
| **#66** | Data Mgmt | No corpus deletion. Hardcoded TRUNCATE in tests (#12) is the only wipe mechanism. | 3 |

## 2. ⚙️ Problem Analysis & Potential Solutions Table

| Ref. | Analysis / Root Cause | Proposed Solution / Approach | Confidence |
| :--- | :--- | :--- | :--- |
| **#64** | State tracking via Postgres `embedding_status` is an abstraction leak that will thrash the DB under bulk Takeout ingestion [Official Architecture Review](file:///home/b08x/WorkspaceV3/sfl-engine/AGENTS.md). | Implement `Ohm` mapping to the existing Docker-compose Redis (port 6380) to handle ephemeral job tracking (`IngestJob`). | 5 |
| **Boot Wiring** | `SFL::Boot` strictly controls external connections to prevent require-time side effects [Composition Root Pattern](file:///home/b08x/WorkspaceV3/sfl-engine/lib/sfl/boot.rb). | Add `REDIS_URL` to `.env`. Add `connect_redis(env)` to `Boot` and assign `Ohm.redis = Redic.new(url)`. | 5 |
| **#51** | The `Takeout` logic is improperly coupled. The engine shouldn't care about the source vendor. | Centralize all traversal and file-hashing logic into an agnostic `Ingest::Orchestrator` that dispatches to format-specific loaders. | 5 |
| **#65** | Synchronous ingestion blocks the UI/CLI. | Expose a `/status` Roda endpoint polling the Redis Ohm sets to stream real-time progress via SSE or WebSockets. | 5 |
| **#54** | Nokogiri parsing is required to transform UI boilerplate into grammatical clauses for the SpaCy sidecar. | Build `html_source.rb` to extract inner text and synthesize complete sentences from fragmented div tags. | 4 |
| **Worker UI** | The background jobs won't run themselves. We must write our own loop since we aren't using ActiveJob. | Create `exe/sfl-worker` that boots the environment, loops over `pending` jobs, rescues StandardError, marks as `failed`, and sleeps if empty. | 4 |

## 3. 📌 Key Findings & Proposed Changes Summary

- **State Management Shift:** Moving the ingestion state tracking from PostgreSQL's `clauses` table to Redis using the `Ohm` rubygem entirely resolves the structural bottleneck of async processing (Primary Evidence).
- **Boot Loader Extensibility:** `SFL::Boot.call` is incredibly well-structured for this change. We can easily mirror the existing `require_db:` logic with `require_redis: true`, ensuring tests can still bypass Redis if needed.
- **Missing CLI Daemon:** The biggest code gap right now isn't the Ohm model, it's the **Daemon**. We need a script (`exe/sfl-worker`) that acts as a continuous loop, picking up where `embedding_redriver.rb` left off, but generalized for the entire ingest pipeline.
- **Consolidation of Intent:** Issues #52, #29, and #51 all funnel into the exact same orchestrator requirement, confirming that the `Ohm` background queue is the highest-leverage task in the backlog.

## 4. 🚀 Potential Optimizations & Next Steps

1. **Update Gemfile & Docker (Issue #64):** Add `gem "ohm"`, `gem "redic"`. Verify `docker-compose.yml` actually exposes Redis on `localhost:6380`.
2. **Modify `SFL::Boot`:** Introduce `REDIS_URL` and `require_redis:` to the signature.
3. **Write `Store::IngestJob`:** Define the Ohm model with the correct `index :state`.
4. **Draft `exe/sfl-worker` (Issue #56 & #63):** Write the continuous polling loop that fetches pending jobs and runs the SpaCy/Ollama pipeline.
5. **Build the Orchestrator (Issue #51):** Write `lib/sfl/core/ingest/orchestrator.rb` to walk a directory, compute file hashes, and push `IngestJob` records to Redis.
6. **Draft Format Loaders (Issue #54 & #55):** Scaffold `html_source.rb` and the multimedia skip-logic.

## 5. 📚 Resource & Tool Assessment Table

| Resource/Tool | Usefulness Assessment | Notes | Rating |
| :--- | :--- | :--- | :--- |
| **Ohm (RubyGem)** | High (Empirical Evidence) | Perfectly maps to the requirement of lightweight, Rails-free Redis job queues via set intersections (`SINTER`/`SUNION`). | 5 |
| **Nokogiri** | High (Primary Evidence) | Required for Issue #54 to clean HTML files from Google Takeout. | 5 |
| **Roda** | High (Primary Evidence) | Designated framework for the API server (#36, #41) due to low overhead and routing tree efficiency. | 5 |
| **Redic (RubyGem)** | High (Empirical Evidence) | The lightweight Redis client Ohm relies on. Much leaner than the standard `redis-rb` gem. | 4 |

## 6. 💻 Revised Code/Solution Overview

### The State Machine Model
```ruby
# lib/sfl/store/models/ingest_job.rb
require 'ohm'

module SFL
  module Store
    class IngestJob < Ohm::Model
      attribute :document_id
      attribute :file_path
      attribute :state # pending, pass_one, embedding, pass_two, done, failed
      attribute :error_trace

      index :state
      index :document_id
    end
  end
end
```

### The Composition Root Modification
```ruby
# lib/sfl/boot.rb
module_function def call(
  env: ENV,
  load_dotenv: true,
  require_db: true,
  require_redis: true, # NEW FLAG
  require_llm: true,
  # ...
)
  Dotenv.load if load_dotenv
  # ...
  db = require_db ? connect_db(env) : nil
  redis = require_redis ? connect_redis(env) : nil # NEW WIRING
  # ...
  Result.new(db:, redis:, llm_config:, ...)
end

module_function def connect_redis(env)
  url = env["REDIS_URL"] || "redis://localhost:6380/0"
  require "ohm"
  Ohm.redis = Redic.new(url)
  Ohm.redis
rescue StandardError => e
  raise Error, "Redis connection failed for #{url}: #{e.message}"
end
```

## 7. 📈 Overall System Health/Viability Assessment

**Health Score: 4**
The foundation is highly robust. Because the engine was built with a strict Composition Root (`SFL::Boot`), injecting a completely new state storage backend (Redis/Ohm) requires zero changes to the core pipeline logic. The system is perfectly primed to absorb this infrastructure addition, though the API routing and ingestion worker loop remain totally unimplemented.

## 8. 💡 Development Tip

When querying Redis via Ohm for your API dashboard, use Ohm's native sizing methods (`IngestJob.find(state: "pending").size`) rather than mapping the results into Ruby arrays. Ohm will execute a rapid `SCARD` (Set Cardinality) command directly on the Redis server, returning the count instantly without loading the job IDs into application memory. Additionally, when building `exe/sfl-worker`, avoid a tight loop polling the queue (`while true; pending = IngestJob.find(...)`); instead, use exponential backoff or Redis blocking pops to prevent 100% CPU usage on an idle server.
