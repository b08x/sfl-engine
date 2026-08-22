# frozen_string_literal: true

require "spec_helper"

# lib/sfl/tui is autoloaded like the rest of the tree (unlike lib/sfl/gui,
# which the loader ignores), but nothing else in the app requires the charm
# gems, so the entry point is required explicitly here rather than relying on
# some other spec having tripped the autoload first.
require "sfl/tui/app"

module TUISpecSupport
  # The six fields SFL::Boot.call(require_db: true, require_llm: false,
  # require_tracing: false) actually populates. llm_config/lm_factory/
  # embedder/classifier stay nil under that call, and this fake keeps them nil
  # on purpose so a pane that reaches for one fails in a spec, not in a
  # terminal.
  def self.boot_result(db: nil)
    SFL::Boot::Result.new(
      db:,
      pass1_command: ["python3"],
      pass1_env: { "PYTHONPATH" => "/tmp/sfl-python" },
      spacy_model: "en_core_web_sm",
      api_debug_errors: false,
      api_cors_origins: []
    )
  end

  def self.context(width: 120, height: 40)
    SFL::TUI::AppContext.new(
      boot: boot_result,
      logger: SFL::Core::Ports::Null::Logger.new,
      width:,
      height:
    )
  end
end
