# sfl-compilerV2

Rebuild of [sfl-compiler](../sfl-compiler) — a single, non-gem Ruby application (no gemspec,
no `gem install`; clone and run). See `rebuild-blueprint-with-plugin.md` for the full SIFT
audit and phased backlog, and the `sfl-compiler-rebuild` track in trackboi (stored against the
legacy repo, since that's this session's active trackboi project) for the current, corrected
architecture decisions layered on top of that blueprint.

## Layout

```
lib/sfl/
├── core/      # types, ports, pass1 sidecar client, pass2 engine, pipeline, loaders
├── store/     # Sequel/pg/pgvector: repositories, migrations, retrieval
├── llm/       # ruby_llm + ruby_llm-schema annotators, per-task model/provider config
├── prompts/   # plain folder of prompt templates
├── cli/       # non-interactive/scriptable analyzer commands
├── gui/       # glimmer-dsl-libui desktop GUI (opt-in require, see lib/sfl.rb)
└── chat/      # interactive chatbot agent (RubyLLM::Tool wrappers around core/ ports)
```

One Zeitwerk loader rooted at `lib/` (see `lib/sfl.rb`). `experiments/` is quarantined —
never autoloaded, never shipped.

## Status

Phase 0 (safety net & triage) in progress. No pipeline code yet.
