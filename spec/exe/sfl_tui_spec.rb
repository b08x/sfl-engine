# frozen_string_literal: true

require "open3"
require "rbconfig"
require "spec_helper"

# Runs exe/sfl-tui in a child process against an empty schema of the test
# database (search_path points at it), so the schema check fails before the
# terminal UI starts.
RSpec.describe "exe/sfl-tui" do # rubocop:disable RSpec/DescribeClass -- an executable, not a class
  let(:root) { File.expand_path("../..", __dir__) }
  let(:schema) { "sfl_tui_unmigrated_#{Process.pid}" }

  before { SFL::Store::StoreTestDb.db.run("CREATE SCHEMA #{schema}") }
  after { SFL::Store::StoreTestDb.db.run("DROP SCHEMA IF EXISTS #{schema} CASCADE") }

  it "prints the schema error to stderr and exits non-zero against an unmigrated database" do
    env = { "DATABASE_URL" => "#{SFL::Store::StoreTestDb::TEST_DATABASE_URL}?search_path=#{schema}", "SFL_AUTO_START_DOCKER" => nil }
    out, err, status = Open3.capture3(env, RbConfig.ruby, File.join(root, "exe/sfl-tui"), chdir: root, stdin_data: "")

    expect(status.exitstatus).to eq(1)
    expect(err).to match(/\Asfl-tui: database \S+ is at schema version 0, latest is \d+; run `bundle exec rake db:migrate`\n\z/)
    expect(out).to be_empty
  end
end
