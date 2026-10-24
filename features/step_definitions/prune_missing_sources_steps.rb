# frozen_string_literal: true

# Step definitions for features/prune_missing_sources.feature.
#
# The database is SFL::Store::StoreTestDb (the test database, never DATABASE_URL).
# Rake scenarios run `bundle exec rake <task>` as a child process against that
# database, so the exit status, stdout and stderr are the real ones. A source
# lookup failure (Errno::EACCES and the like) is injected into the child with a
# preload file that wraps File.stat for the one path named in the scenario.
# Fixtures live under <project>/tmp/, which .gitignore covers.

require "fileutils"
require "open3"
require "rspec/expectations"
require "tmpdir"
require "sfl"
require_relative "../../spec/support/store_test_db"

module PruneMissingSourcesSteps
  PROJECT_ROOT = File.expand_path("../..", __dir__)
  FIXTURE_PARENT = File.join(PROJECT_ROOT, "tmp")
  TEST_DATABASE_URL = SFL::Store::StoreTestDb::TEST_DATABASE_URL

  # Each run: command, stdout, stderr, status (Integer), snapshot after the run.
  RunResult = Struct.new(:command, :stdout, :stderr, :status, :snapshot, keyword_init: true)

  def pms_db = SFL::Store::StoreTestDb.db

  def pms_ids = (@pms_ids ||= {})

  def pms_failures = (@pms_failures ||= {})

  def pms_runs = (@pms_runs ||= [])

  def pms_values = (@pms_values ||= {})

  def pms_dir = @pms_dir

  # Holds the preload file, outside the fixture directory so the listing check stays exact.
  def pms_stub_dir = (@pms_stub_dir ||= Dir.mktmpdir("prune-qa-stub-", PruneMissingSourcesSteps::FIXTURE_PARENT))

  def pms_collection_id
    @pms_collection_id ||= pms_db[:collections].get(:id) || pms_db[:collections].insert(name: "claude-chats")
  end

  def pms_full_snapshot
    db = pms_db
    {
      documents: db[:documents].order(:id).all,
      sections: db[:sections].order(:id).all,
      clauses: db[:clauses].order(:id).all,
    }
  end

  # Rows of one document, its sections and its clauses, from a full snapshot.
  def pms_scope(snapshot, key)
    ids = pms_ids.fetch(key)
    {
      document: snapshot[:documents].find { |row| row[:document_key] == key },
      sections: snapshot[:sections].select { |row| ids[:section_ids].include?(row[:section_id]) },
      clauses: snapshot[:clauses].select { |row| ids[:clause_ids].include?(row[:external_id]) },
    }
  end

  def pms_document_row(key) = pms_db[:documents].where(document_key: key).first

  def pms_last_line(text) = text.lines.last.to_s.chomp

  def pms_run(command)
    task = command[/\Arake (.+)\z/, 1]
    raise ArgumentError, "not a rake command: #{command}" unless task

    preload = File.join(pms_stub_dir, "stat_stub.rb")
    File.write(preload, pms_preload_source)
    env = {
      "DATABASE_URL" => TEST_DATABASE_URL,
      "SFL_LOG_TARGET" => "stderr",
      "SFL_LOG_LEVEL" => "info",
      "RUBYOPT" => "-r#{preload}",
    }
    stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "rake", task, chdir: PROJECT_ROOT)
    pms_runs << RunResult.new(command:, stdout:, stderr:, status: status.exitstatus, snapshot: pms_full_snapshot)
  end

  def pms_preload_source
    <<~RUBY
      # frozen_string_literal: true

      # Test-only: makes File.stat raise the configured errno for the listed paths.
      module PruneMissingSourcesStatStub
        FAILURES = #{pms_failures.inspect}.freeze

        def stat(path, *rest, **kwargs, &block)
          errno = FAILURES[path.to_s]
          raise Errno.const_get(errno), path.to_s if errno

          super
        end
      end
      File.singleton_class.prepend(PruneMissingSourcesStatStub)
    RUBY
  end

  def pms_warnings(stderr, component)
    stderr.lines.select { |line| line.start_with?("[WARN]") && line.include?("component=#{component}") }
  end

  def pms_field(line, name) = line[/\b#{name}=(\S+)/, 1]

  def pms_seed_document(key, source_path:, archived:, sections: 0, clauses: 0)
    document_id = pms_db[:documents].insert(
      collection_id: pms_collection_id, document_key: key, source_path:,
      section_count: sections, archived_at: (Time.now if archived)
    )
    section_ids = Array.new(sections) { |i| "#{key}#turn-#{i}" }
    section_ids.each_with_index do |section_id, ordinal|
      pms_db[:sections].insert(section_id:, document_id:, ordinal:, kind: "turn")
    end
    clause_ids = Array.new(clauses) { |i| "#{key}-clause-#{i}" }
    clause_ids.each_with_index do |external_id, i|
      section_id = section_ids[i % [sections, 1].max] if sections.positive?
      pms_db[:clauses].insert(external_id:, text: "text of #{external_id}", section_id:, sentence_index: i,
        root_index: 0)
      pms_db[:ideational_payloads].insert(clause_id: external_id, process_type: "material")
      pms_db[:interpersonal_payloads].insert(clause_id: external_id, mood: "declarative")
    end
    pms_ids[key] = { document_id:, section_ids:, clause_ids: }
  end

  def pms_key_for_clause(clause_id)
    pms_ids.find { |_key, ids| ids[:clause_ids].include?(clause_id) }&.first
  end

  def pms_cleanup
    FileUtils.rm_f(File.expand_path(@pms_outside)) if @pms_outside
    FileUtils.remove_entry(@pms_dir) if @pms_dir && File.exist?(@pms_dir)
    FileUtils.remove_entry(@pms_stub_dir) if @pms_stub_dir && File.exist?(@pms_stub_dir)
    SFL::Store::StoreTestDb.clean! if @pms_dir || @pms_ids
  end
end

World(PruneMissingSourcesSteps)
World(RSpec::Matchers)

After do
  pms_cleanup
end

# Background and setup

Given(/\Aa database with a collection "([^"]+)"\z/) do |name|
  SFL::Store::StoreTestDb.clean!
  @pms_collection_id = pms_db[:collections].insert(name:)
  @pms_ids = {}
end

Given(/\Aa temporary directory holding "([^"]+)" as a source file\z/) do |name|
  FileUtils.mkdir_p(PruneMissingSourcesSteps::FIXTURE_PARENT)
  @pms_dir = Dir.mktmpdir("prune-qa-", PruneMissingSourcesSteps::FIXTURE_PARENT)
  File.write(File.join(@pms_dir, name), "{}")
end

PRUNE_DOCUMENT_HEAD = 'document "([^"]+)" with source_path pointing at "([^"]+)", which (exists|does not exist)'

Given(/\A#{PRUNE_DOCUMENT_HEAD}, archived_at (null|set to a timestamp), with (\d+) sections? and (\d+) clauses?\z/o) do |key, name, _existence, archived, sections, clauses|
  pms_seed_document(key, source_path: File.join(pms_dir, name), archived: archived != "null",
    sections: Integer(sections), clauses: Integer(clauses))
end

Given(/\Adocument "([^"]+)" with source_path (""|null), archived_at null\z/) do |key, raw|
  pms_seed_document(key, source_path: ((raw == "null") ? nil : ""), archived: false)
end

Given(/\Aa file "([^"]+)" in the temporary directory's parent, and document "([^"]+)" whose source_path is "([^"]+)" which exists, archived_at null\z/) do |file, key, relative|
  @pms_outside = File.join(pms_dir, "..", file)
  File.write(@pms_outside, "outside the collection\n")
  pms_seed_document(key, source_path: File.join(pms_dir, relative), archived: false)
end

Given(/\Athe file's bytes and modification time are recorded\z/) do
  path = File.expand_path(@pms_outside)
  pms_values[:outside] = { path:, bytes: File.binread(path), mtime: File.mtime(path) }
  pms_values[:listing] = Dir.children(pms_dir).sort.to_h { |name| [name, File.mtime(File.join(pms_dir, name))] }
end

Given(/\Athe source path lookup of "([^"]+)" raises (Errno::\w+)\z/) do |key, errno|
  pms_failures[pms_document_row(key)[:source_path]] = errno.delete_prefix("Errno::")
end

Given(/\Athe rows of "([^"]+)", its sections and its clauses are recorded\z/) do |_key|
  @pms_recording = pms_full_snapshot
end

Given(/\Athe row of "([^"]+)" and its sections and clauses are recorded(?:, including its updated_at value)?\z/) do |_key|
  @pms_recording = pms_full_snapshot
end

Given("the database rows are recorded") do
  @pms_recording = pms_full_snapshot
end

Given(/\Athe archived_at of "([^"]+)" is recorded as (\w+)\z/) do |key, name|
  pms_values[name.to_sym] = pms_document_row(key)[:archived_at]
end

Given(/\A"([^"]+)" is archived\z/) do |key|
  pms_db[:documents].where(document_key: key, archived_at: nil).update(archived_at: Time.now)
  raise "#{key} is not archived" if pms_document_row(key)[:archived_at].nil?
end

Given(/\A"([^"]+)" has archived_at (not null|null) and a clause whose text matches the query "([^"]+)"\z/) do |key, state, query|
  pms_db[:documents].where(document_key: key).update(archived_at: ((state == "not null") ? Time.now : nil))
  clause_id = pms_ids.fetch(key)[:clause_ids].first
  pms_db[:clauses].where(external_id: clause_id).update(text: "a #{query} kept by #{key}")
end

# When

When(/\AI run "(.+)"\z/) do |command|
  pms_run(command)
end

When(/\AI run "(.+)" a second time\z/) do |command|
  pms_run(command)
end

When("the time before the run is recorded as T0") do
  pms_values[:T0] = Time.now.floor(6)
end

When("the time after the run is recorded as T1") do
  pms_values[:T1] = Time.now.ceil(6)
end

When("I run a default context retrieval for {string} with no archive opt-in") do |query|
  retriever = SFL::Store::PgHybridRetriever.new(db: pms_db, embedder: SFL::Core::Ports::Null::Embedder.new)
  @pms_results = retriever.retrieve(SFL::Core::Types::RetrievalQuery.new(query:))
end

# Then: exit status and output

Then(/\Athe exit status is (\d+)\z/) do |code|
  run = pms_runs.last
  expect(run.status).to eq(Integer(code)), "exit status #{run.status}; stderr: #{run.stderr}"
end

Then("the exit status is non-zero") do
  run = pms_runs.last
  expect(run.status).not_to eq(0), "exit status was 0; stdout: #{run.stdout}"
end

Then(/\Athe last line of output is "(.*)"\z/) do |expected|
  expect(pms_last_line(pms_runs.last.stdout)).to eq(expected)
end

Then(/\Athe second run's last line of output is "(.*)"\z/) do |expected|
  expect(pms_last_line(pms_runs[1].stdout)).to eq(expected)
end

Then(/\Athe last line of output counts "([^"]+)" in kept_unreadable\z/) do |_key|
  expect(pms_last_line(pms_runs.last.stdout)).to match(/ kept_unreadable=1\z/)
end

Then(/\Athe output is a notice that "([^"]+)" (is already archived|is not archived)\z/) do |key, phrase|
  output = pms_runs.last.stdout + pms_runs.last.stderr
  expect(output).to include("#{key} #{phrase}")
end

Then(/\Athe output names the key "([^"]+)" and says no document matched\z/) do |key|
  output = pms_runs.last.stdout + pms_runs.last.stderr
  expect(output).to include(key)
  expect(output).to include("no document matched")
end

Then(/\Aexactly one warning is logged with keyword fields component "([^"]+)", document_key "([^"]+)", and reason "([^"]+)"\z/) do |component, key, reason|
  lines = pms_warnings(pms_runs.last.stderr, component)
  expect(lines.size).to eq(1), "expected one warning, got #{lines.size}: #{lines.join}"
  expect(pms_field(lines.first, "document_key")).to eq(key)
  expect(pms_field(lines.first, "reason")).to eq(reason)
  @pms_warning_line = lines.first
end

# Limited to the prune reasons. An unrestricted "([^"]+)" also matches the
# JSON records steps' reason-only phrasing and makes both ambiguous.
Then(/\Aexactly one warning is logged with reason "(source_unreadable|source_path_missing)"\z/) do |reason|
  lines = pms_warnings(pms_runs.last.stderr, "PruneMissingSources")
  expect(lines.size).to eq(1), "expected one warning, got #{lines.size}: #{lines.join}"
  expect(pms_field(lines.first, "reason")).to eq(reason)
  @pms_warning_line = lines.first
end

Then("the warning contains no source path and no message text") do
  line = @pms_warning_line
  expect(line).to match(/\A\[WARN\]\s+component=PruneMissingSources /)
  expect(line).not_to include(pms_dir)
end

# Then: documents, sections, clauses

Then(/\Adocument "([^"]+)" no longer exists\z/) do |key|
  expect(pms_db[:documents].where(document_key: key).count).to eq(0)
end

Then(/\Ano section row with document "([^"]+)" exists\z/) do |key|
  ids = pms_ids.fetch(key)[:section_ids]
  expect(pms_db[:sections].where(section_id: ids).count).to eq(0)
end

Then(/\Ano clause row whose section belonged to "([^"]+)" exists\z/) do |key|
  ids = pms_ids.fetch(key)[:clause_ids]
  expect(pms_db[:clauses].where(external_id: ids).count).to eq(0)
end

Then(/\Adocument "([^"]+)" still exists(?: with its sections? and clauses?)?\z/) do |key|
  ids = pms_ids.fetch(key)
  expect(pms_document_row(key)).not_to be_nil
  expect(pms_db[:sections].where(section_id: ids[:section_ids]).count).to eq(ids[:section_ids].size)
  expect(pms_db[:clauses].where(external_id: ids[:clause_ids]).count).to eq(ids[:clause_ids].size)
  @pms_subject = key
end

Then("its archived_at is not null") do
  expect(pms_document_row(@pms_subject)[:archived_at]).not_to be_nil
end

Then(/\Athe rows of "([^"]+)", its sections and its clauses are identical to the recording\z/) do |key|
  expect(pms_scope(pms_full_snapshot, key)).to eq(pms_scope(@pms_recording, key))
end

Then(/\Athe database rows are identical to the recording(?:, including updated_at)?\z/) do
  expect(pms_full_snapshot).to eq(@pms_recording)
end

Then("the database rows after the second run are identical to the rows after the first run") do
  expect(pms_runs[1].snapshot).to eq(pms_runs[0].snapshot)
end

Then(/\Athe archived_at of "([^"]+)" is not null and is between T0 and T1\z/) do |key|
  archived_at = pms_document_row(key)[:archived_at]
  expect(archived_at).not_to be_nil
  expect(archived_at).to be_between(pms_values.fetch(:T0), pms_values.fetch(:T1))
end

Then(/\Athe archived_at of "([^"]+)" is null\z/) do |key|
  expect(pms_document_row(key)[:archived_at]).to be_nil
end

Then(/\Athe archived_at of "([^"]+)" is A0, with the same value, and no new timestamp is written\z/) do |key|
  expect(pms_document_row(key)[:archived_at]).to eq(pms_values.fetch(:A0))
end

Then(/\Ano other column of the "([^"]+)" row changed, including updated_at\z/) do |key|
  before_row = pms_scope(@pms_recording, key)[:document].except(:archived_at)
  after_row = pms_scope(pms_full_snapshot, key)[:document].except(:archived_at)
  expect(after_row).to eq(before_row)
end

Then("no section or clause row changed") do
  current = pms_full_snapshot
  expect(current[:sections]).to eq(@pms_recording[:sections])
  expect(current[:clauses]).to eq(@pms_recording[:clauses])
end

Then("no document row changed") do
  expect(pms_full_snapshot[:documents]).to eq(@pms_recording[:documents])
end

# Then: file system

Then(/\Athe file "([^"]+)" exists with the recorded bytes and modification time\z/) do |_name|
  recorded = pms_values.fetch(:outside)
  expect(File.binread(recorded[:path])).to eq(recorded[:bytes])
  expect(File.mtime(recorded[:path])).to eq(recorded[:mtime])
end

Then("no file in the temporary directory was created, renamed or removed by the prune") do
  listing = Dir.children(pms_dir).sort.to_h { |name| [name, File.mtime(File.join(pms_dir, name))] }
  expect(listing).to eq(pms_values.fetch(:listing))
end

# Then: retrieval

Then(/\Ano result has document_key "([^"]+)"\z/) do |key|
  clause_ids = @pms_results.map(&:clause_id)
  expect(clause_ids & pms_ids.fetch(key)[:clause_ids]).to be_empty
end

Then(/\Athe result includes the clause of "([^"]+)"\z/) do |key|
  clause_ids = @pms_results.map(&:clause_id)
  expect(clause_ids & pms_ids.fetch(key)[:clause_ids]).not_to be_empty
end
