require "dotenv"

module Config
  class << self
    def get
      Dotenv.load if not_production?

      @config ||= {
        secret: ENV["SESSION_SECRET"] || 'DEV-ONLY-8<FQF8HiF)>l0hbPk£vBQ#IrYsoO}14k\l+-/gIU[j}l0hbPk£vBQ#IrY',
        environment: environment,
        db: {
          url: ENV["DATABASE_URL"] || (not_production? ? "postgres://user:password@localhost:5432/app_#{environment}" : nil)
        }
      }
    end

    def not_production? = environment != "production"
    def environment
      ENV["RACK_ENV"] || "development"
    end
  end
end
