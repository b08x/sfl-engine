repo: b08x/sfl-engine
branch: development

## Last sync
date: 2026-08-02T05:46:38Z
### Updated in this project
- Built the initial 5-screen operator console (Corpus Browser, Annotation Review Queue, Content Review Queue, Query Console, Ad-hoc Compile) from the HTTP API surface documented in `docs/project-overview.md` and `lib/sfl/api/server.rb` — no prior frontend existed in the repo.
- Field/enum names (mood, process_type, modality_weight, tenor, annotation_source, decision values, response shapes) grounded directly in `lib/sfl/api/server.rb`.

## Screen map
| Screen | Repo grounding |
|---|---|
| Corpus Browser + Clause Detail | `lib/sfl/api/server.rb` (`GET /clauses`), `docs/project-overview.md` (AnnotatedClause shape) |
| Annotation Review Queue | `lib/sfl/api/server.rb` (`GET /clauses/review-queue`, `POST /clauses/:id/review`) |
| Content Review Queue | `lib/sfl/api/server.rb` (`GET /review-queue`, `POST /review-queue/:id/decide`) |
| Query Console | `lib/sfl/api/server.rb` (`POST /retrieve`, `POST /synthesize`) |
| Ad-hoc Compile | `lib/sfl/api/server.rb` (`POST /pipeline/compile`) |
