# frozen_string_literal: true

# Step definitions for features/json_records_source.feature. Files are built
# in a tmp directory per scenario. Database scenarios write through
# SFL::Store::PgSectionRegistry on the test database (StoreTestDb). Steps the
# two features share (the When "the loader yields its units", "no warning is
# logged", "exactly N units are yielded") are defined in
# sillytavern_source_steps.rb and read the same instance variables: @units,
# @logger and @error.

require "fileutils"
require "json"
require "tmpdir"
require "sfl"
require_relative "../../spec/support/store_test_db"

module JsonRecordsSteps
  # Scenario helpers: loader runs, the store, batches and assertions. File builders are in Files.

  def jr_init
    @jr_active = true
    @logger ||= CaptureLogger.new
    @jr_file = "conversations.json" if @jr_file.nil?
  end

  def jr_ledger = (@jr_ledger ||= {})

  def jr_db
    @jr_db_ready ||= (SFL::Store::StoreTestDb.clean!; true)
    SFL::Store::StoreTestDb.db
  end

  def jr_batch
    ledger = jr_ledger
    db = jr_db
    SFL::Core::Loaders::JsonRecordsBatch.new(
      registry_factory: -> { LedgerRegistry.new(SFL::Store::PgSectionRegistry.new(db, collection: "json-records-steps"), ledger) },
      logger: @logger
    )
  end

  def jr_expected_fields(text)
    fields = {}
    text.scan(/(\w+) (equal to the file's byte size|"[^"]*"|\d+)/) do |key, raw|
      fields[key.to_sym] = if raw.start_with?("equal") then :size
      elsif raw.start_with?('"') then raw[1..-2]
      else raw.to_i
      end
    end
    fields
  end

  def jr_run_units(path)
    ref = SFL::Core::Refs::FileRefBuilder.call(path, source_id: path)
    SillyTavernSourceSteps.io_log = @record_io ? [] : nil
    begin
      SFL::Core::Loaders::JsonRecordsSource.new(ref, logger: @logger).each_unit.to_a
    ensure
      @io_log = SillyTavernSourceSteps.io_log
      SillyTavernSourceSteps.io_log = nil
    end
  end

  # Runs the loader for the scenario. Shared With SillyTavern's When step.
  def jr_yield_units
    @error = nil
    @jr_count = nil
    path = @source_path || @jr_generated_path || jr_path(@jr_file)
    if @jr_discard
      @jr_count = 0
      @jr_peak_before = jr_peak_kib
      begin
        ref = SFL::Core::Refs::FileRefBuilder.call(path, source_id: path)
        SFL::Core::Loaders::JsonRecordsSource.new(ref, logger: @logger).each_unit { |unit| @jr_count += 1 if unit.section_id }
      rescue SFL::Core::Loaders::Error => e
        @error = e
      end
      @jr_peak_after = jr_peak_kib
      return []
    end
    jr_run_units(path)
  rescue SFL::Core::Loaders::Error => e
    @error = e
    []
  end

  def jr_peak_kib = File.read("/proc/self/status")[/VmHWM:\s+(\d+)/, 1].to_i

  # Rows by natural key. Surrogate ids are left out: a re-ingest may replace a
  # section row, and the ids of a rolled-back run still advance the sequences.
  # The document id is kept under :ids for the id-stability check.
  def jr_snapshot
    documents = jr_db[:documents].order(:document_key).map do |row|
      row.slice(:document_key, :source_path, :title, :source_type, :section_count)
    end
    sections = jr_db[:sections].join(:documents, id: :document_id).order(:section_id).all.map do |row|
      row.slice(:section_id, :document_key, :ordinal, :kind, :label, :clause_count).merge(text: jr_ledger[row[:section_id]])
    end
    ids = jr_db[:documents].select_map(%i[document_key id]).to_h
    { documents:, sections:, ids:, section_ids: jr_db[:sections].select_hash(:section_id, :id) }
  end

  def jr_section_row(section_id) = jr_db[:sections].where(section_id:).first

  def jr_fail(message) = raise(Failed, message)

  def jr_assert(condition, message)
    jr_fail(message) unless condition
  end

  def jr_uuid_list(text) = text.scan(/"([^"]+)"/).flatten

  def jr_summary_failed(name, reason)
    entry = @summary[:failed].find { |item| item[:file] == name }
    jr_assert(entry && entry[:reason] == reason, "#{name} not failed with #{reason}: #{@summary[:failed].inspect}")
    entry
  end
end

World(JsonRecordsSteps, JsonRecordsSteps::Files)

After do
  FileUtils.rm_rf(@jr_dir) if @jr_dir
end

# Background

Given(/\Aa JSON file named "([^"]+)" whose top-level value is written as given in each scenario\z/) do |name|
  jr_init
  @jr_file = name
end

Given(/\Aa loader constructed as SFL::Core::Loaders::JsonRecordsSource\.new\(ref\)\z/) do
  jr_init
end

# Conversation records. A clause is parsed by MESSAGE, and a "cut off" clause is a truncated record.

Given(/\A(?!.*(?:one message whose "text" is|first message whose "text" is|100,000 nested|contains a raw|named "|whose "chat_messages"|uuid))(?:the array holds |the file holds |file "([^"]+)" holds |then )?(conversation ".*)\z/) do |file, text| # rubocop:disable Layout/LineLength
  jr_init
  @jr_file = file if file
  jr_add_segments(@jr_file, text)
end

Given(/\Athen conversation "([^"]+)" whose "chat_messages" array is cut off after its first message's opening brace, and the file ends there\z/) do |uuid|
  jr_init
  jr_add_raw(@jr_file, %({"uuid": "#{uuid}", "chat_messages": [{), truncated: true)
end

Given(/\Aa top-level array whose first element is (.+), followed by conversation "([^"]+)" with one message "([^"]+)"\z/) do |record, uuid, text|
  jr_init
  jr_add_raw(@jr_file, record)
  jr_add_conversation(@jr_file, uuid, %( with one message "#{text}"))
end

Given(/\Aa top-level array holding only the records (.+) and (.+)\z/) do |first, second|
  jr_init
  jr_add_raw(@jr_file, first)
  jr_add_raw(@jr_file, second)
end

Given(/\Aa file whose content is "(.*)"\z/) do |content|
  jr_init
  jr_state(@jr_file)[:raw] = content
end

Given(/\Afile "([^"]+)" whose content is (.+)\z/) do |name, content|
  jr_init
  @jr_file = name
  jr_state(name)[:raw] = content
end

Given(/\Aconversation "([^"]+)" with one message whose "text" is (\[.*\]|\{.*\})\z/) do |uuid, value|
  jr_init
  jr_add_raw(@jr_file, %({"uuid": "#{uuid}", "chat_messages": [{"sender": "human", "text": #{value}}]}))
end

Given(/\Aconversation "([^"]+)" with one message whose "text" is the string "(.*)"\z/) do |uuid, value|
  jr_init
  text = value.gsub('\"', '"')
  jr_add_part(@jr_file, JSON.generate({ "uuid" => uuid, "chat_messages" => [{ "sender" => "human", "text" => text }] }))
end

Given(/\Aa message whose "text" is "([^"]+)" and whose "content" holds one block of type "text" with text "([^"]+)"\z/) do |text, block|
  jr_init
  jr_add_part(@jr_file, JSON.generate({ "uuid" => "c-alpha", "chat_messages" => [{ "sender" => "human", "text" => text, "content" => [{ "type" => "text", "text" => block }] }] }))
end

Given(/\Aconversation "([^"]+)" with a first message whose "text" is 5 MiB \(5,242,880 bytes\) of ordinary text, followed by a message "([^"]+)"\z/) do |uuid, after|
  jr_init
  big = "a" * 5_242_880
  jr_add_part(@jr_file, JSON.generate({ "uuid" => uuid, "chat_messages" => [{ "sender" => "human", "text" => big }, { "sender" => "human", "text" => after }] }))
end

Given(/\Aconversation "([^"]+)" named "(.*)", with a first message whose "text" is "" and a second message "([^"]+)"\z/) do |uuid, name, second|
  jr_init
  title = name.gsub('\n', "\n")
  jr_add_part(@jr_file, JSON.generate({ "uuid" => uuid, "name" => title, "chat_messages" => [{ "sender" => "human", "text" => "" }, { "sender" => "human", "text" => second }] }))
end

Given(/\Aconversation with uuid "(.*?)"(?: followed by a line feed and "([^"]*)")?,? (?:with |and )messages "([^"]+)" and "([^"]+)", followed by conversation "([^"]+)" with one message "([^"]+)"\z/m) do |uuid, feed, one, two, next_uuid, after| # rubocop:disable Layout/LineLength
  jr_init
  key = uuid.gsub('\n', "\n")
  key = "#{key}\n#{feed}" if feed
  jr_add_part(@jr_file, JSON.generate({ "uuid" => key, "chat_messages" => [{ "text" => one }, { "text" => two }] }))
  jr_add_part(@jr_file, JSON.generate({ "uuid" => next_uuid, "chat_messages" => [{ "text" => after }] }))
end

Given(/\Aconversation with uuid "c-" followed by 100 "a" characters and then "#", with message "one", followed by conversation "c-beta" with one message "after"\z/) do
  jr_init
  key = "c-#{'a' * 100}#"
  jr_add_part(@jr_file, JSON.generate({ "uuid" => key, "chat_messages" => [{ "text" => "one" }] }))
  jr_add_part(@jr_file, JSON.generate({ "uuid" => "c-beta", "chat_messages" => [{ "text" => "after" }] }))
end

Given(/\Aconversation "([^"]+)" with messages "([^"]+)" and a message whose "text" contains a raw U\+0001 control character, then message "([^"]+)"\z/) do |uuid, one, three|
  jr_init
  raw = %({"uuid": "#{uuid}", "chat_messages": [{"text": "#{one}"}, {"text": "abcd"}, {"text": "#{three}"}]})
  jr_add_raw(@jr_file, raw)
end

Given(/\Aconversation "([^"]+)" with a message whose "text" is 100,000 nested arrays, the innermost holding "deep"\z/) do |uuid|
  jr_init
  nested = "#{'[' * 100_000}\"deep\"#{']' * 100_000}"
  jr_add_raw(@jr_file, %({"uuid": "#{uuid}", "chat_messages": [{"sender": "human", "text": #{nested}}]}))
end

Given(/\Aa file named "(.*)" whose only conversation has a message whose "text" is ""\z/) do |name|
  jr_init
  @jr_file = name.gsub('\n', "\n")
  jr_add_part(@jr_file, JSON.generate({ "uuid" => "c-alpha", "chat_messages" => [{ "sender" => "human", "text" => "" }] }))
end

Given(/\Athen a stray "\}" in place of the comma after conversation "([^"]+)", followed by conversation "([^"]+)" with one message "([^"]+)"\z/) do |_first, uuid, text|
  jr_init
  jr_add_part(@jr_file, "}", glue: true, stray: true)
  jr_add_part(@jr_file, JSON.generate({ "uuid" => uuid, "chat_messages" => [{ "text" => text }] }))
end

Given(/\Aa generated file of about 64 MiB holding 2,000 conversations of 2 messages each\z/) do
  jr_init
  path = File.join(jr_dir, @jr_file)
  text = "x" * 16_000
  File.open(path, "wb") do |io|
    io.write("[")
    2_000.times do |index|
      io.write(", ") if index.positive?
      io.write(JSON.generate({ "uuid" => "c-#{index}", "chat_messages" => [{ "text" => text }, { "text" => text, "sender" => "assistant" }] }))
    end
    io.write("]")
  end
  @jr_generated_path = path
end

Given(/\Aa budget of 16 MiB, measured as the growth of the process's peak resident memory during the load\z/) do
  jr_init
  @jr_budget_kib = 16 * 1024
end

# "a file ref for ... inside a directory that also holds" and "file-open and
# directory-listing calls are recorded" are SillyTavern steps. They write the
# file, set @source_path and turn on @record_io.

# When

When(/\Athe loader yields its units and the caller discards each unit after reading its section id\z/) do
  jr_init
  @jr_discard = true
  @units = jr_yield_units
end

When(/\AI ingest "([^"]+)" as a single-file run\z/) do |name|
  jr_init
  @error = nil
  @source = jr_batch.ingest_one(jr_ref(name))
rescue SFL::Core::Loaders::Error => e
  @error = e
end

When(/\AI ingest "([^"]+)", then "([^"]+)", then "([^"]+)" again\z/) do |first, second, third|
  jr_init
  @jr_snapshots = [first, second, third].map do |name|
    jr_batch.ingest_one(jr_ref(name))
    jr_snapshot
  end
end

When(/\AI ingest "([^"]+)" twice\z/) do |name|
  jr_init
  @jr_snapshots = Array.new(2) do
    jr_batch.ingest_one(jr_ref(name))
    jr_snapshot
  end
end

When(/\AI run a batch over (".+")\z/) do |list|
  jr_init
  names = list.scan(/"([^"]+)"/).flatten
  @summary = jr_batch.call(names.map { |name| jr_ref(name) })
end

# Two batch runs on one store. @summary is the second run's; the first run's section ids are kept for the surrogate-id check.
When(/\Abatch run "([^"]+)" is followed by batch run "([^"]+)"\z/) do |first, second|
  jr_init
  @first_summary = jr_batch.call([jr_ref(first)])
  @jr_ids_after_first = jr_db[:sections].select_hash(:section_id, :id)
  @summary = jr_batch.call([jr_ref(second)])
end

When(/\Athe loader yields its units and the warnings are written to the stderr log target\z/) do
  jr_init
  @units = jr_yield_units
end

# Then: unit assertions

Then(/\Athe first unit's text equals the 5 MiB text byte for byte, with a bytesize of 5,242,880\z/) do
  text = @units.first.text
  jr_assert(text.bytesize == 5_242_880 && text.match?(/\A a+\z/x), "unit text bytesize #{text.bytesize}")
end

Then(/\Athat unit's text is "(.*)"\z/) do |expected|
  jr_assert(@units.first.text == expected.gsub(", one line break, ", "\n"), "text #{@units.first.text.inspect}")
end

Then(/\Aits text is the literal string (.+)\z/) do |expected|
  jr_assert(@units.first.text == expected, "text #{@units.first.text.inspect}")
end

Then(/\Athe section id is "([^"]+)"\z/) do |section_id|
  jr_assert(@units.first.section_id == section_id, "section id #{@units.first.section_id}")
end

Then(/\A(?:the|its) section id is "([^"]+)" and its text is "([^"]+)"\z/) do |section_id, text|
  unit = @units.first
  jr_assert(unit.section_id == section_id && unit.text == text, "unit #{unit.section_id} #{unit.text.inspect}")
end

Then(/\Ano unit has a section id containing "([^"]+)"\z/) do |fragment|
  jr_assert(@units.none? { |unit| unit.section_id.include?(fragment) }, "a section id contains #{fragment}")
end

Then(/\Aexactly (\d{1,3}(?:,\d{3})+) units are yielded\z/) do |count|
  actual = @jr_count || @units.size
  jr_assert(actual == count.delete(",").to_i, "#{actual} units yielded, expected #{count}")
end

Then(/\Athe section ids are (.+?)(?:, in that order)?\z/) do |list|
  expected = jr_uuid_list(list)
  jr_assert(@units.map(&:section_id) == expected, "section ids #{@units.map(&:section_id).inspect}")
end

Then(/\Aunits? ([\d, and]+) have document_key "([^"]+)"\z/) do |indexes, key|
  indexes.scan(/\d+/).map(&:to_i).each { |index| jr_assert(@units[index].document_key == key, "unit #{index} key #{@units[index].document_key}") }
end

Then(/\Aunit (\d+) has document_key "([^"]+)"\z/) do |index, key|
  jr_assert(@units[index.to_i].document_key == key, "unit #{index} key #{@units[index.to_i].document_key}")
end

Then(/\Aunits ([\d, and]+) have is_user (true|false), and unit (\d+) has is_user (true|false)\z/) do |indexes, flag, other, other_flag|
  indexes.scan(/\d+/).map(&:to_i).each { |index| jr_assert(@units[index].is_user == (flag == "true"), "unit #{index} is_user") }
  jr_assert(@units[other.to_i].is_user == (other_flag == "true"), "unit #{other} is_user")
end

Then(/\Athe (first|second) unit's text is "([^"]*)" and its section id is "([^"]+)"\z/) do |which, text, section_id|
  unit = { "first" => @units.first, "second" => @units[1] }.fetch(which)
  jr_assert(unit.text == text && unit.section_id == section_id, "#{which} unit #{unit.text.inspect} #{unit.section_id}")
end

Then(/\Athe texts of those units are (.+?)(?:, in that order)?\z/) do |list|
  jr_assert(@units.map(&:text) == jr_uuid_list(list), "texts #{@units.map(&:text).inspect}")
end

Then(/\Aits document_key is the first 64 characters of that uuid\z/) do
  expected = "c-#{'a' * 100}#"[0, 64]
  jr_assert(@logger.warnings.last[:fields][:document_key] == expected, "key #{@logger.warnings.last[:fields][:document_key].inspect}")
end

Then(/\Ano unit has that uuid as document_key\z/) do
  key = "c-#{'a' * 100}#"[0, 64]
  jr_assert(@units.none? { |unit| unit.document_key == key }, "a unit has that key")
end

Then(/\Ano unit has document_key "([^"]+)"\z/) do |key|
  jr_assert(@units.none? { |unit| unit.document_key == key }, "a unit has document_key #{key}")
end

Then(/\Ano unit has text ("[^"]*"(?:, "[^"]*")*,? (?:or|and) "[^"]*")\z/) do |list|
  texts = jr_uuid_list(list)
  jr_assert(@units.none? { |unit| texts.include?(unit.text) }, "a unit has one of #{texts.inspect}")
end

Then(/\Aexactly (\d+) units? (?:is|are) yielded, with (.+)\z/) do |count, pairs|
  jr_assert(@units.size == count.to_i, "#{@units.size} units yielded")
  unit = @units.first
  pairs.scan(/(section id|document_key|text) "([^"]*)"/) do |field, value|
    actual = { "section id" => unit.section_id, "document_key" => unit.document_key, "text" => unit.text }.fetch(field)
    jr_assert(actual == value, "#{field} #{actual.inspect}")
  end
end

Then(/\Athe unit's metadata "conversation_title" is "(.*)", unchanged\z/) do |title|
  jr_assert(@units.first.metadata["conversation_title"] == title.gsub('\n', "\n"), "title #{@units.first.metadata['conversation_title'].inspect}")
end

Then(/\Athe loader either yields exactly 1 unit whose text is "deep", or raises an error with reason "parse_error", file "conversations\.json" and an integer byte_offset, and yields no unit\z/) do # rubocop:disable Layout/LineLength
  if @error
    jr_assert(@error.reason == "parse_error" && @error.byte_offset.is_a?(Integer), "error #{@error.reason}")
    jr_assert(@units.empty?, "units yielded with error")
  else
    jr_assert(@units.size == 1 && @units.first.text == "deep", "units #{@units.size}")
  end
end

Then(/\Athe process does not terminate with a stack overflow error\z/) do
  jr_assert(@error.nil? || @error.is_a?(SFL::Core::Loaders::Error), "unexpected error #{@error}")
end

Then(/\Athe loader gets file content only through the ref\z/) do
  jr_assert(@io_log.any? { |entry| entry[:method] == :open && entry[:path] == File.expand_path(@source_path.to_s) }, "content not read through the ref")
end

Then(/\A"secrets\.json" is never opened, read or stat'd\z/) do
  jr_assert(@io_log.none? { |entry| entry[:path].end_with?("secrets.json") }, "secrets.json was touched")
end

Then(/\Athe peak resident memory growth during the load is under 16 MiB\z/) do
  growth = @jr_peak_after - @jr_peak_before
  jr_assert(growth < @jr_budget_kib, "peak growth #{growth} KiB")
end

# Then: logging

# The prune feature uses the same phrasing with its own reasons; those are
# excluded here so the two step sets do not match the same step text.
Then(/\Aexactly one warning is logged with reason "(?!source_unreadable"|source_path_missing")([^"]+)"(?: and document_key "([^"]+)")?\z/) do |reason, key|
  jr_assert(@logger.warnings.size == 1, "#{@logger.warnings.size} warnings")
  fields = @logger.warnings.first[:fields]
  jr_assert(fields[:reason] == reason && (key.nil? || fields[:document_key] == key), "fields #{fields.inspect}")
end

Then(/\Aexactly one warning is logged with keyword fields (?!component "PruneMissingSources")(?!.*, line \d+, and reason)(.+)\z/) do |pairs|
  jr_assert(@logger.warnings.size == 1, "#{@logger.warnings.size} warnings")
  expected = jr_expected_fields(pairs)
  expected[:byte_offset] = jr_file_size(expected[:file] || @jr_file) if expected[:byte_offset] == :size
  fields = @logger.warnings.first[:fields]
  mismatch = expected.reject { |key, value| fields[key] == value }
  jr_assert(mismatch.empty?, "fields differ #{mismatch.inspect}; actual #{fields.inspect}")
end

Then(/\Athe warning contains no message text and no uuid\z/) do
  values = @logger.warnings.flat_map { |warning| [warning[:message], *warning[:fields].values] }.grep(String)
  jr_assert(values.none? { |value| value.include?("c-") || value.include?("three") || value.include?("one") }, "warning leaks text")
end

Then(/\Athe warning contains no message text and no conversation name\z/) do
  values = @logger.warnings.flat_map { |warning| [warning[:message], *warning[:fields].values] }.grep(String)
  jr_assert(values.none? { |value| value.include?("three") || value.include?("Chat") }, "warning leaks text")
end

Then(/\Athe warning field "file" is "([^"]+)"\z/) do |name|
  jr_assert(@logger.warnings.last[:fields][:file] == name, "file #{@logger.warnings.last[:fields][:file].inspect}")
end

Then(/\Ano warning message or field contains the text "([^"]+)"\z/) do |text|
  values = @logger.warnings.flat_map { |warning| [warning[:message], *warning[:fields].values] }.grep(String)
  jr_assert(values.none? { |value| value.include?(text) }, "a warning contains #{text}")
end

Then(/\Athe warning is written as exactly one line\z/) do
  values = @logger.warnings.flat_map { |warning| [warning[:message], *warning[:fields].values] }.grep(String)
  jr_assert(values.none? { |value| value.match?(/[\r\n]/) }, "a warning spans lines")
end

Then(/\Ano warning with reason "([^"]+)" is logged\z/) do |reason|
  jr_assert(@logger.warnings.none? { |warning| warning[:fields][:reason] == reason }, "a warning has reason #{reason}")
end

# Then: store rows

Then(/\Aan SFL::Core::Loaders::Error is raised with (.+)\z/) do |detail|
  jr_assert(@error.is_a?(SFL::Core::Loaders::Error), "no Loaders::Error raised")
  reason = detail[/reason "([^"]+)"/, 1]
  file = detail[/file "([^"]+)"/, 1]
  jr_assert(@error.reason == reason, "reason #{@error.reason}") if reason
  jr_assert(@error.file == file, "file #{@error.file}") if file
  if detail.include?("the file's byte size")
    jr_assert(@error.byte_offset == jr_file_size(file || @jr_file), "byte_offset #{@error.byte_offset}")
  elsif detail.include?('the offset of that "}"')
    jr_assert(@error.byte_offset == @jr_stray_offset, "byte_offset #{@error.byte_offset}, stray #{@jr_stray_offset}")
  elsif detail.include?("an integer byte_offset")
    jr_assert(@error.byte_offset.is_a?(Integer), "byte_offset #{@error.byte_offset.inspect}")
  end
end

Then(/\Ano document row and no section row exists for the file\z/) do
  jr_assert(jr_db[:documents].none? && jr_db[:sections].none?, "rows exist")
end

Then(/\Ano document row and no section row exists for (".+")\z/) do |list|
  jr_uuid_list(list).each do |uuid|
    jr_assert(jr_db[:documents].where(document_key: uuid).none?, "document #{uuid} exists")
    jr_assert(jr_db[:sections].where(Sequel.like(:section_id, "#{uuid}#%")).none?, "sections for #{uuid} exist")
  end
end

Then(/\Ano document row exists for "([^"]+)"\z/) do |uuid|
  jr_assert(jr_db[:documents].where(document_key: uuid).none?, "document #{uuid} exists")
end

Then(/\Aexactly one document row exists with document_key "([^"]+)"\z/) do |uuid|
  jr_assert(jr_db[:documents].where(document_key: uuid).one?, "document count for #{uuid}")
end

Then(/\Aexactly two section rows exist for "([^"]+)", with section ids (.+)\z/) do |uuid, list|
  ids = jr_db[:sections].join(:documents, id: :document_id).where(document_key: uuid).select_map(:section_id).sort
  jr_assert(ids == jr_uuid_list(list).sort, "section ids #{ids.inspect}")
end

Then(/\Athe document row's id is the same after each ingest\z/) do
  ids = @jr_snapshots.map { |snap| snap[:ids]["c-alpha"] }
  jr_assert(ids.uniq.size == 1 && !ids.first.nil?, "ids #{ids.inspect}")
end

Then(/\Aeach section row keeps its surrogate id after each ingest\z/) do
  first = @jr_snapshots.first[:section_ids]
  jr_assert(!first.empty?, "no section rows")
  @jr_snapshots.each_with_index do |snap, index|
    jr_assert(snap[:section_ids] == first, "section ids changed at ingest #{index + 1}: #{snap[:section_ids].inspect}")
  end
end

Then(/\Athe section row "([^"]+)" has the text "([^"]+)" after the second ingest\z/) do |section_id, text|
  row = @jr_snapshots[1][:sections].find { |section| section[:section_id] == section_id }
  jr_assert(row && row[:text] == text, "text #{row&.fetch(:text).inspect}")
end

Then(/\Aafter the third ingest the section row "([^"]+)" has the text "([^"]+)"\z/) do |section_id, text|
  row = @jr_snapshots[2][:sections].find { |section| section[:section_id] == section_id }
  jr_assert(row && row[:text] == text, "text #{row&.fetch(:text).inspect}")
end

Then(/\Ano section row or document row is created or deleted by the second or third ingest beyond the first ingest's rows\z/) do
  first = @jr_snapshots.first
  @jr_snapshots.each do |snap|
    jr_assert(snap[:documents].size == first[:documents].size && snap[:sections].size == first[:sections].size, "row counts changed")
  end
end

Then(/\Athe database rows after the second ingest are identical to the rows after the first ingest, except for the ingest timestamp\z/) do
  jr_assert(@jr_snapshots[0].slice(:documents, :sections) == @jr_snapshots[1].slice(:documents, :sections), "rows differ")
end

Then(/\Athe batch run summary lists "([^"]+)" as failed with reason "([^"]+)"(?: and byte_offset equal to the file's byte size)?\z/) do |name, reason|
  entry = jr_summary_failed(name, reason)
  jr_assert(entry[:byte_offset] == jr_file_size(name), "byte_offset #{entry[:byte_offset]}") if entry[:reason] == "truncated"
end

Then(/\Athe batch run summary counts (\d+) failed files?(?: and (\d+) redundant files?)?\z/) do |failed, redundant|
  jr_assert(@summary[:failed].size == failed.to_i, "failed #{@summary[:failed].size}")
  jr_assert(@summary[:redundant].size == redundant.to_i, "redundant #{@summary[:redundant].size}") if redundant
end

Then(/\Athe batch run summary lists one skipped entry for "([^"]+)" with reason "([^"]+)" and record_index (\d+)\z/) do |name, reason, index|
  entry = { file: name, record_index: index.to_i, reason: }
  jr_assert(@summary[:skipped] == [entry], "skipped #{@summary[:skipped].inspect}")
end

Then(/\Athe batch run summary reports stale_removed (\d+)\z/) do |count|
  jr_assert(@summary[:stale_removed] == count.to_i, "stale_removed #{@summary[:stale_removed]}")
end

Then(/\Athe section "([^"]+)" is absent\z/) do |section_id|
  jr_assert(jr_section_row(section_id).nil?, "section #{section_id} is present")
end

Then(/\Athe section ids "([^"]+)" and "([^"]+)" are unchanged by the second run\z/) do |first, second|
  current = jr_db[:sections].select_hash(:section_id, :id)
  [first, second].each do |section_id|
    jr_assert(current[section_id] && current[section_id] == @jr_ids_after_first[section_id], "surrogate id of #{section_id} changed")
  end
end

Then(/\Athe document row "([^"]+)" has section_count (\d+)\z/) do |document_key, count|
  row = jr_db[:documents].where(document_key:).first
  jr_assert(row && row[:section_count] == count.to_i, "section_count #{row && row[:section_count]}")
end

Then(/\Athe store holds exactly the rows that a batch over "([^"]+)" alone produces\z/) do |name|
  current = jr_snapshot
  jr_db[:sections].delete
  jr_db[:documents].delete
  jr_ledger.clear
  jr_batch.call([jr_ref(name)])
  jr_assert(jr_snapshot.slice(:documents, :sections) == current.slice(:documents, :sections), "rows differ from a batch over #{name} alone")
end

Then(/\Athe section rows? (.+?) from "[^"]+" (?:are|is) present(?:,? with texts? (.+))?\z/) do |ids_text, texts_text|
  ids = jr_uuid_list(ids_text)
  texts = texts_text ? jr_uuid_list(texts_text) : []
  ids.each_with_index do |id, index|
    jr_assert(jr_section_row(id), "section #{id} missing")
    jr_assert(jr_ledger[id] == texts[index], "text of #{id} is #{jr_ledger[id].inspect}") if texts[index]
  end
end

Then(/\Ano row holds the text "([^"]+)"\z/) do |text|
  present = jr_db[:sections].select_map(:section_id).map { |id| jr_ledger[id] }
  jr_assert(present.none?(text), "a row holds #{text}")
end

Then(/\Ano section row has a section id containing "([^"]+)"\z/) do |fragment|
  jr_assert(jr_db[:sections].select_map(:section_id).none? { |id| id.include?(fragment) }, "a section id contains #{fragment}")
end
