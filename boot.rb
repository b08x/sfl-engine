# frozen_string_literal: true

require "bundler/setup"
Bundler.require

# Autoloading setup
# lib/sfl is already configured in lib/sfl.rb, which we require here
# app/ needs its own loader for the Roda application structure
require_relative "lib/sfl"

# Set up Zeitwerk for app/ directory
app_loader = Zeitwerk::Loader.new
app_loader.tag = "app"
app_loader.push_dir("#{__dir__}/app")
# Collapse directories to avoid redundant namespace segments
app_loader.collapse("#{__dir__}/app/services")
app_loader.collapse("#{__dir__}/app/config")
app_loader.collapse("#{__dir__}/app/models")
app_loader.inflector.inflect("db" => "DB")
app_loader.setup

# Development tools
if Config.not_production?
  begin
    require "debug"
  rescue LoadError
    # debug gem not available in this Ruby install, skip silently
  end
end

# Initialize providers for the Roda application
# These are defined in app/config/providers/ and provide the basic
# infrastructure needed by the web app (database, logging, mail)
SFL::DockerServices.ensure_running!
Providers::DB::Conn.boot
Providers::Mailer.boot
Providers::Logger.boot

# Set up database constant for convenience
DB = Providers::DB::Conn.get

# Reuse SFL::Boot for LLM/tracing collaborators (require_db: false — the
# Roda-managed `DB` above is already connected with the extensions
# Store::Database needs; SFL::Boot's own connect_db would be redundant).
sfl_boot = SFL::Boot.call(
  load_dotenv: false,
  require_db: false,
  require_llm: ENV["SFL_SKIP_LLM_BOOT"] != "true",
  require_tracing: ENV["SFL_ENABLE_TRACING"] == "true"
)
sfl_boot.db = DB
Providers::Engine.boot(sfl_boot)

# Automatic model annotations in development environment
if Config.not_production?
  begin
    require "sequel/annotate"
    Sequel::Annotate.annotate(Dir["app/models/*.rb"], position: :before, border: true)
  rescue LoadError
    # sequel/annotate not available, skip silently
  end
end
