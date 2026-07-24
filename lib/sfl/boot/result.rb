# frozen_string_literal: true

module SFL
  module Boot
    # Everything a CLI/TUI entry point needs after calling Boot.call, in
    # one bundle — mirrors the role of legacy Bootstrap::Context, but
    # shaped for v2's actual (per-task, not global) collaborators rather
    # than copying that struct's fields:
    #
    # - `db`: connected Sequel::Database (nil if require_db: false), no
    #   migrations run (see Store::Database's own comment — that's
    #   `rake db:migrate`'s job, never Boot's).
    # - `llm_config`: the built SFL::LLM::Config (nil if require_llm: false).
    # - `chat_factory`: ready-to-use SFL::LLM::ChatFactory for building
    #   Engine/ContextSynthesizer via EngineBuilder etc. (nil if
    #   require_llm: false).
    # - `embedder`: ready-to-use SFL::LLM::Embedder for --store-style
    #   commands that need real embeddings (nil if require_llm: false).
    # - `pass1_command`: the resolved `command:` array to pass to
    #   SpacySidecarParser.new(command:, ...), or nil when
    #   .sfl-python/interpreter_path hasn't been provisioned yet (in which
    #   case the caller should omit `command:` entirely and let
    #   SpacySidecarParser fall back to its own `python3` default).
    # - `spacy_model`: resolved SPACY_MODEL, always present — needed
    #   whether or not pass1_command is nil (SpacySidecarParser's
    #   `model:` kwarg is required either way).
    Result = Struct.new(:db, :llm_config, :chat_factory, :embedder, :pass1_command, :spacy_model, keyword_init: true)
  end
end
