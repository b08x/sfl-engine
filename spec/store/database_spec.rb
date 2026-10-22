# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::Database do
  describe ".connect" do
    it "returns a Sequel::Database connected to the given url" do
      db = described_class.connect(SFL::Store::StoreTestDb::TEST_DATABASE_URL)

      begin
        expect(db).to be_a(Sequel::Database)
        expect(db.test_connection).to be true
      ensure
        db.disconnect
      end
    end

    it "requires the url; Boot resolves DATABASE_URL (fact 72)" do
      expect { described_class.connect }.to raise_error(ArgumentError)
    end
  end

  describe ".setup_extensions" do
    it "is idempotent against a database that already has both extensions" do
      db = SFL::Store::StoreTestDb.db

      expect { described_class.setup_extensions(db) }.not_to raise_error
    end
  end
end
