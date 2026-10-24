# frozen_string_literal: true

# Step definitions for features/sillytavern_source.feature. Each scenario gets
# its own session files in a tmp directory; sample sessions are read in place
# from output/eval/_src/sim_chats/ and never written.

require "fileutils"
require "json"
require "stringio"
require "tmpdir"
require "time"
require "sfl"

module SillyTavernSourceSteps
  class Failed < StandardError; end

  SAMPLE_DIR = File.expand_path("../../output/eval/_src/sim_chats", __dir__)
  LOADER_PATH = File.expand_path("../../lib/sfl/core/loaders/sillytavern_source.rb", __dir__)

  # Records each path that File or Dir receives while a scenario has IO recording on.
  FILE_CALLS = %i[open read new stat lstat size readlines foreach exist? file? binread].freeze
  DIR_CALLS = %i[entries children each_child glob open foreach].freeze

  # Thread-local so that only the scenario's own loader run is recorded.
  def self.io_log = Thread.current[:sillytavern_io_log]

  def self.io_log=(log)
    Thread.current[:sillytavern_io_log] = log
  end

  def self.log_io(kind, method, path)
    io_log&.push({ kind:, method:, path: path.to_s })
  end

  # Prepended spy: records the call, then runs the real method.
  def self.spy(kind, methods)
    Module.new do
      methods.each do |name|
        define_method(name) do |*args, **kwargs, &block|
          SillyTavernSourceSteps.log_io(kind, name, args.first)
          super(*args, **kwargs, &block)
        end
      end
    end
  end

  File.singleton_class.prepend(spy(:file, FILE_CALLS))
  Dir.singleton_class.prepend(spy(:dir, DIR_CALLS))

  # Stands in for Ports::Logger and keeps every warn call.
  class CaptureLogger
    include SFL::Core::Ports::Logger

    attr_reader :warnings

    def initialize
      @warnings = []
    end

    def warn(message = nil, **fields, &block)
      @warnings << { message: message || block&.call, fields: }
    end

    def debug(*, **) = nil
    def info(*, **) = nil
    def error(*, **) = nil
    def fatal(*, **) = nil
  end

  def st_assert(condition, message)
    raise Failed, message unless condition
  end

  def st_unescape(text) = text.gsub('\n', "\n")

  def st_turn(name: "Steve", mes: "hello", is_user: false, send_date: "June 15, 2024 6:35pm")
    { "name" => name, "is_user" => is_user, "is_system" => false, "send_date" => send_date, "mes" => mes }
  end

  def st_header
    {
      "name" => "SillyTavern System",
      "is_user" => false,
      "is_system" => true,
      "is_group" => true,
      "mes" => "Group chat created...",
    }
  end

  def st_dir = (@st_dir ||= Dir.mktmpdir)

  # Writes the scenario's physical lines (or raw content) to the session file.
  def st_write_session
    text = @content || "#{@records.map { |record| record.is_a?(String) ? record : JSON.generate(record) }.join("\n")}\n"
    path = File.join(st_dir, @file_name)
    File.write(path, text)
    File.utime(@mtime, @mtime, path) if @mtime
    path
  end

  def st_path = (@st_path ||= @source_path || st_write_session)

  # Runs the loader the way the ingest boundary does: rescues Loaders::Error and keeps stderr quiet.
  def st_run(path, file_id: @file_id)
    @error = nil
    @logger = CaptureLogger.new
    stderr = $stderr
    $stderr = StringIO.new
    SillyTavernSourceSteps.io_log = @record_io ? [] : nil
    begin
      ref = SFL::Core::Refs::FileRefBuilder.call(path, source_id: path)
      SFL::Core::Loaders::SillyTavernSource.new(ref, file_id:, logger: @logger).each_unit.to_a
    rescue SFL::Core::Loaders::Error => e
      @error = e
      []
    ensure
      @io_log = SillyTavernSourceSteps.io_log
      SillyTavernSourceSteps.io_log = nil
      @stderr = $stderr.string
      $stderr = stderr
    end
  end

  def st_unit(which)
    { "first" => @units.first, "second" => @units[1], "last" => @units.last }.fetch(which)
  end

  def st_expected_count(path)
    File.foreach(path).map { |line| JSON.parse(line) }.count { |record| record["is_system"] != true }
  end

  def st_utc(text) = Time.iso8601(text).utc.iso8601
end

World(SillyTavernSourceSteps)

After do
  FileUtils.rm_rf(@st_dir) if @st_dir
end

Given(/\Aa SillyTavern group-chat session file written as JSONL\z/) do
  @records = []
  @content = nil
  @file_name = "session.jsonl"
  @file_id = "st-session"
  @mtime = nil
  @source_path = nil
  @sample_paths = []
  @record_io = false
  @pending_system = nil
  @io_log = nil
  @units = nil
  @error = nil
  @logger = nil
  @stderr = ""
  @mes_value = nil
  @send_date_text = nil
end

Given(/\Aa file ref for that path built with the helper the loader specs use/) do
  # The ref is built by st_run through SFL::Core::Refs::FileRefBuilder, as spec/support/file_ref_helper.rb does.
end

Given(/\Aa loader constructed as SFL::Core::Loaders::SillyTavernSource\.new\(ref, file_id: "st-session"\)\z/) do
  # The loader is constructed in st_run with the file_id set by the scenario.
end

# Scenario: system records

Given(/\Aa session file whose first record is the system header/) do
  @records << st_header
end

Given(/\Athe file has a second system record with "is_system" true between its turn records\z/) do
  @pending_system = {
    "name" => "SillyTavern System",
    "is_user" => false,
    "is_system" => true,
    "mes" => "System note",
  }
end

Given(/\Athe file has 3 non-system turn records besides those two system records\z/) do
  @records << st_turn(name: "Steve", mes: "one")
  @records << @pending_system if @pending_system
  @records << st_turn(name: "Mason", mes: "two") << st_turn(name: "Robert", mes: "three")
end

# Scenario: order and section ids

Given(/\Aa session file with turn records from "(.*)", "(.*)" and "(.*)" in that order\z/) do |first, second, third|
  @records = [first, second, third].map { |name| st_turn(name:) }
end

Then(/\Athe units' section ids are "(.*)", "(.*)" and "(.*)"\z/) do |first, second, third|
  st_assert(@units.map(&:section_id) == [first, second, third], "section ids #{@units.map(&:section_id)}")
end

Then(/\Athe units' speakers are "(.*)", "(.*)" and "(.*)" in that order\z/) do |first, second, third|
  st_assert(@units.map(&:speaker) == [first, second, third], "speakers #{@units.map(&:speaker)}")
end

Then(/\Aeach unit's parent_section_id is nil\z/) do
  st_assert(@units.all? { |unit| unit.parent_section_id.nil? }, "parent_section_id is not nil")
end

Then(/\Aeach unit's heading is nil\z/) do
  st_assert(@units.all? { |unit| unit.heading.nil? }, "heading is not nil")
end

# Scenario Outline: speaker and is_user

Given(/\Aa session file with a turn record whose "name" is "(.*)" and whose "is_user" is (true|false)\z/) do |name, flag|
  @records = [st_turn(name:, is_user: flag == "true")]
end

Then(/\Athe unit's speaker is "(.*)"\z/) do |name|
  st_assert(@units.first.speaker == name, "speaker #{@units.first.speaker}")
end

Then(/\Athe unit's is_user is (true|false)\z/) do |flag|
  st_assert(@units.first.is_user == (flag == "true"), "is_user #{@units.first.is_user}")
end

# Scenario Outline and boundary scenarios: send_date

Given(/\Aa session file whose mtime is (\S+)\z/) do |stamp|
  @mtime = Time.iso8601(stamp)
end

Given(/\Aa turn record with "send_date" "(.*)"\z/) do |send_date|
  @records = [st_turn(send_date:)]
end

Then(/\Athat unit's sent_at is (\S+)\z/) do |expected|
  st_assert(@units.first.sent_at.utc.iso8601 == expected, "sent_at #{@units.first.sent_at.utc.iso8601}")
end

Then(/\Athat unit's sent_at is a Time whose UTC offset is zero\z/) do
  st_assert(@units.first.sent_at.is_a?(Time) && @units.first.sent_at.utc_offset.zero?, "sent_at is not UTC")
end

Then(/\Athat unit's sent_at does not equal the file mtime\z/) do
  st_assert(@units.first.sent_at != @mtime, "sent_at equals the file mtime")
end

Given(/\Aa session file with turn records whose "send_date" values are "(.*)" and "(.*)" in that order\z/) do |first, second|
  @records = [st_turn(send_date: first), st_turn(send_date: second)]
end

Then(/\Athe (first|second) unit's sent_at is (\S+), which is UTC-\d\z/) do |which, expected|
  actual = st_unit(which).sent_at.utc.iso8601
  st_assert(actual == expected, "#{which} sent_at #{actual}")
end

Then(/\Athe difference between the two units' sent_at values is (\d+) seconds(?:, .*)?\z/) do |seconds|
  st_assert((@units.last.sent_at - @units.first.sent_at).to_i == seconds.to_i, "difference is not #{seconds}")
end

# Scenario: multi-line records

Given(/\Aa session file with these physical lines:\z/) do |doc|
  @records = doc.lines.map(&:chomp)
end

Then(/\Athe (first|second|last) unit's text is "([^"]*)"\z/) do |which, expected|
  st_assert(st_unit(which).text == st_unescape(expected), "text #{st_unit(which).text.inspect}")
end

Then(/\Athe (first|second) unit's text is "([^"]*)", then one line break character, then "([^"]*)"\z/) do |which, before, after|
  st_assert(st_unit(which).text == "#{before}\n#{after}", "text #{st_unit(which).text.inspect}")
end

Then(/\Athe unit's text is:\z/) do |doc|
  st_assert(@units.size == 1 && @units.first.text == doc, "text #{@units.first&.text.inspect}")
end

# Scenario: a session file with no trailing line break

Given(/\Aa session file with a system header, then two turn records "(.*)" and "(.*)", where the final record has no line break after it\z/) do |first, last|
  @content = [st_header, st_turn(mes: first), st_turn(mes: last)].map { |record| JSON.generate(record) }.join("\n")
end

# Scenario: malformed record

Given(/\Aa session file whose physical line 3 is '(.*)'\z/) do |raw|
  @bad_line = raw
end

Given(/\Alines 1, 2, 4 and 5 are valid turn records\z/) do
  @records = [st_turn(mes: "one"), st_turn(mes: "two"), @bad_line, st_turn(mes: "four"), st_turn(mes: "five")]
end

Then(/\Athe error's file field is the basename of the session file\z/) do
  st_assert(@error&.file == @file_name, "error file #{@error&.file.inspect}")
end

Then(/\Athe error's line field is (\d+), the physical line that is not valid JSON\z/) do |line|
  st_assert(@error&.line == line.to_i, "error line #{@error&.line.inspect}")
end

Then(/\Aexactly one SFL::Core::Loaders::Error is raised\z/) do
  st_assert(@error.is_a?(SFL::Core::Loaders::Error), "no Loaders::Error raised")
end

Then(/\Ano unit is yielded(?! for the line).*\z/) do
  st_assert(@units.empty?, "#{@units.size} units yielded")
end

Then(/\Athe ingest boundary rescues the error without aborting the surrounding ingest run\z/) do
  # st_run plays the ingest boundary: it rescued the Loaders::Error and returned control.
  st_assert(@error.is_a?(SFL::Core::Loaders::Error), "no Loaders::Error was rescued")
end

# Scenario: ref extension

Given(/\Aa ref whose path ends in "(.*)"\z/) do |extension|
  @file_name = "session#{extension}"
  @records = [st_turn] if @records.empty?
end

Then(/\Aa SFL::Core::Loaders::Error is raised(.*)\z/) do |detail|
  st_assert(@error.is_a?(SFL::Core::Loaders::Error), "no Loaders::Error raised")
  st_assert(@error.message.include?(@file_name), "error does not name #{@file_name}") if detail.include?("naming the file")
  st_assert(@error.line.is_a?(Integer), "error has no line") if detail.include?("the line")
end

Then(/\Ano SFL::Core::Loaders::Error is raised\z/) do
  st_assert(@error.nil?, "unexpected #{@error&.message}")
end

# Scenario Outline: empty and header-only files

Given(/\Aa session file whose content is "(.*)"\z/) do |content|
  @content = content
end

# Scenario: metadata and document identity

Given(/\Aa session file at a filesystem path whose basename is "(.*)"\z/) do |name|
  @file_name = name
  @records = [st_turn] if @records.empty?
end

Given(/\Athe loader was constructed with file_id "(.*)"\z/) do |file_id|
  @file_id = file_id
end

Then(/\Aevery unit's document_key is the ref's path_hint\z/) do
  st_assert(@units.all? { |unit| unit.document_key == File.expand_path(st_path) }, "document_key differs")
end

Then(/\Aevery unit's source_path is the ref's path_hint\z/) do
  st_assert(@units.all? { |unit| unit.source_path == File.expand_path(st_path) }, "source_path differs")
end

Then(/\Aevery unit's metadata equals (\{.*\})\z/) do |literal|
  expected = JSON.parse(literal.gsub("=>", ":"))
  st_assert(@units.all? { |unit| unit.metadata == expected }, "metadata differs from #{expected}")
end

Given(/\Aa session file named "(.*)" containing (\d+) turn records\z/) do |name, count|
  @file_name = name
  @records = Array.new(count.to_i) { |index| st_turn(mes: "turn #{index}") }
end

Then(/\Aevery unit's metadata "source_file" is "(.*)"\z/) do |name|
  st_assert(@units.all? { |unit| unit.metadata["source_file"] == name }, "source_file differs")
end

# Scenario Outline: sample sessions

Given(/\Athe sample session file "(.*)"\z/) do |name|
  path = File.join(SillyTavernSourceSteps::SAMPLE_DIR, name)
  @sample_paths << path
  @source_path = path
end

Then(/\Aevery unit's speaker is a non-empty String\z/) do
  st_assert(@units.all? { |unit| unit.speaker.is_a?(String) && !unit.speaker.empty? }, "speaker empty")
end

Then(/\Aevery unit's sent_at is a Time, not nil\z/) do
  st_assert(@units.all? { |unit| unit.sent_at.is_a?(Time) }, "sent_at nil")
end

Then(/\Athe (first|second|last) unit's section id is "(.*)"\z/) do |which, expected|
  st_assert(st_unit(which).section_id == expected, "section id #{st_unit(which).section_id}")
end

# Scenario: two files under their own file_id

When(/\Athe loader yields units for each file under its own file_id\z/) do
  @units_by_file = @sample_paths.each_with_index.map do |path, index|
    st_run(path, file_id: "st-#{index}")
  end
end

Then(/\Aeach file yields its own units with document_key set to that file's path_hint\z/) do
  st_assert(@units_by_file.zip(@sample_paths).all? { |units, path| units.all? { |u| u.document_key == File.expand_path(path) } },
    "document_key differs")
end

Then(/\Athe two document_keys are different\z/) do
  keys = @units_by_file.map { |units| units.first.document_key }
  st_assert(keys.uniq.size == 2, "document_keys match")
end

Then(/\Ano unit is dropped or merged because another file has the same turn count or the same content\z/) do
  counts = @units_by_file.map(&:size)
  expected = @sample_paths.map { |path| st_expected_count(path) }
  st_assert(counts == expected, "counts #{counts} expected #{expected}")
end

Then(/\Athe loader itself performs no deduplication across files\z/) do
  total = @units_by_file.sum(&:size)
  st_assert(total == @sample_paths.sum { |path| st_expected_count(path) }, "total units #{total}")
end

# Scenario Outline: untrusted content

Given(/\Aa session file containing (.*)\z/) do |case_text|
  @records = case case_text
             when /raw U\+0001/ then [%({"name":"Steve","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:35pm","mes":"ab\u0001cd"})]
             when /73 KB/ then [st_turn(mes: ("ordinary text " * 6000)[0, 73 * 1024])]
             else raise Failed, "unknown case #{case_text}"
  end
  @mes_value ||= @records.first["mes"] if @records.first.is_a?(Hash)
end

Then(/\Aexactly one unit is yielded whose text equals the mes value byte for byte\z/) do
  st_assert(@units.size == 1 && @units.first.text == @mes_value, "units #{@units.size}")
end

# Scenario: markup and content as data

Given(/\Aa turn record whose mes is "(.*)"\z/) do |raw|
  @mes_value = st_unescape(raw)
  @records = [st_turn(mes: @mes_value)]
end

Then(/\Athat unit's text is exactly "(.*)"\z/) do |expected|
  st_assert(@units.first.text == st_unescape(expected), "text #{@units.first.text.inspect}")
end

Then(/\Athe loader does not fetch the URL or any other network address\z/) do
  source = File.read(SillyTavernSourceSteps::LOADER_PATH)
  st_assert(!source.match?(/Net::|Socket|open-uri|URI\.open|Faraday/), "loader references a network API")
end

Then(/\Ano part of the message text is written to stderr or to any log field other than the unit's text\z/) do
  st_assert(@stderr.empty?, "stderr received output")
  leaked = @logger.warnings.any? { |w| w[:message].to_s.include?(@mes_value) || w[:fields].values.any? { |v| v.to_s.include?(@mes_value) } }
  st_assert(!leaked, "message text reached a log")
end

# Scenario Outline: unusable send_date

Given(/\Aa session file with three turn records, where the record at line 2 has (.*)\z/) do |clause|
  rec2 = st_turn(name: "Steve", mes: "two")
  if (match = clause.match(/\Asend_date "(.*)"\z/))
    rec2["send_date"] = match[1]
    @send_date_text = match[1]
  else
    rec2.delete("send_date")
  end
  @records = [st_turn(mes: "one"), rec2, st_turn(mes: "three")]
end

Given(/\Athe records at lines 1 and 3 have send_date "(.*)" and "(.*)"\z/) do |first, third|
  @records[0]["send_date"] = first
  @records[2]["send_date"] = third
end

Then(/\Athe unit at line (\d+) has sent_at nil(?:, .*)?\z/) do |line|
  st_assert(@units[line.to_i - 1].sent_at.nil?, "line #{line} has a sent_at")
end

Then(/\Athe units at lines 1 and 3 have sent_at values (\S+) and (\S+)\z/) do |first, third|
  st_assert(st_utc(first) == @units[0].sent_at.utc.iso8601, "line 1 sent_at")
  st_assert(st_utc(third) == @units[2].sent_at.utc.iso8601, "line 3 sent_at")
end

Then(/\Aexactly one warning is logged .*?, line (\d+), and reason "(.*)"\z/) do |line, reason|
  st_assert(@logger.warnings.size == 1, "#{@logger.warnings.size} warnings")
  fields = @logger.warnings.first[:fields]
  st_assert(fields == { component: "SillyTavernSource", file: @file_name, line: line.to_i, reason: }, "fields #{fields}")
end

Then(/\Athe warning's message string contains neither the send_date value nor the file path\z/) do
  message = @logger.warnings.first[:message].to_s
  st_assert(!message.include?(@file_name), "message names the file")
  st_assert(@send_date_text.to_s.empty? || !message.include?(@send_date_text), "message holds send_date text")
end

Then(/\Athe units at lines 1 and 3 keep their own sent_at values\z/) do
  st_assert(!@units[0].sent_at.nil? && !@units[2].sent_at.nil?, "a neighbour lost its sent_at")
end

# Scenario: crafted send_date

Given(/\Aa turn record at line 2 whose "send_date" is a valid-looking date "(.*?)", then a line break, then the text "(.*)"\z/) do |date, injected|
  @send_date_text = "#{date}\n#{injected}"
  @records = [st_turn(mes: "one"), st_turn(name: "Steve", mes: "two", send_date: @send_date_text), st_turn(mes: "three")]
end

Given(/\Athe records at lines 1 and 3 have valid send_date values\z/) do
  @records[0]["send_date"] = "June 15, 2024 6:35pm"
  @records[2]["send_date"] = "June 15, 2024 6:36pm"
end

Then(/\Ano log message string and no log field contains the crafted text or any part of it\z/) do
  texts = @logger.warnings.flat_map { |w| [w[:message].to_s, *w[:fields].values.map(&:to_s)] }
  ["forged entry", "level=error", "June 19, 2024 2:22pm"].each do |fragment|
    st_assert(texts.none? { |text| text.include?(fragment) }, "log contains #{fragment}")
  end
end

# Scenario: path abuse

Given(/\Aa file ref for "(.*)" inside a directory that also holds "(.*)"\z/) do |relative, sibling|
  session = File.join(st_dir, relative)
  FileUtils.mkdir_p(File.dirname(session))
  record = JSON.generate(st_turn(mes: "inside the ref"))
  File.write(session, "#{record}\n")
  File.write(File.join(File.dirname(session), sibling), "#{record}\n")
  @source_path = session
  @record_io = true
end

Given(/\Afile-open and directory-listing calls are recorded during the load\z/) do
  @record_io = true
end

Then(/\Athe only path opened is the ref's path\z/) do
  opened = @io_log.select { |entry| entry[:kind] == :file }.map { |entry| entry[:path] }.uniq
  st_assert(opened == [File.expand_path(@source_path)], "opened #{opened}")
end

Then(/\Ano directory is listed\z/) do
  st_assert(@io_log.none? { |entry| entry[:kind] == :dir }, "a directory was listed")
end

Then(/\A"secrets\.jsonl" is never opened, read or stat'd\z/) do
  st_assert(@io_log.none? { |entry| entry[:path].end_with?("secrets.jsonl") }, "secrets.jsonl was touched")
end

Then(/\Athe loader gets file content only through the ref's read method\z/) do
  st_assert(@io_log.any? { |entry| entry[:method] == :read && entry[:path] == File.expand_path(@source_path) },
    "content was not read through the ref")
end

# Runs for every scenario after its Given steps: loads the file or sample the scenario named.

# Shared with features/json_records_source.feature, which uses the same phrase.
When(/\Athe loader yields its units\z/) do
  @units = @jr_active ? jr_yield_units : st_run(st_path)
end

Then(/\Aexactly (\d+|one) units? (?:is|are) yielded(?:, each a SFL::Core::Types::Unit|, one per physical line)?\z/) do |count|
  expected = (count == "one") ? 1 : count.to_i
  st_assert(@units.size == expected, "#{@units.size} units yielded, expected #{expected}")
  st_assert(@units.all?(SFL::Core::Types::Unit), "a yielded value is not a Types::Unit")
end

Then(/\Ano unit has text "([^"]*)"\z/) do |text|
  st_assert(@units.none? { |unit| unit.text == st_unescape(text) }, "a unit has text #{text}")
end

Then(/\Ano unit has speaker "(.*)"\z/) do |speaker|
  st_assert(@units.none? { |unit| unit.speaker == speaker }, "a unit has speaker #{speaker}")
end

Then(/\Ano warning is logged for either system record\z/) do
  st_assert(@logger.warnings.empty?, "warnings were logged")
end

# Scenario group: non-String mes, missing mes and neighbour context

# Each JSON object in the docstring is merged over the default turn, so a
# record only names the keys that differ. "mes": null is a missing mes.
Given(/\Aa session file whose records are the JSON array:\z/) do |doc|
  @records = JSON.parse(doc).map { |partial| st_turn.merge(partial) }
end

Given(/\Aa session file whose first record is a turn record "(.*)" whose mes is 5 MiB \(5,242,880 bytes\) of ordinary text\z/) do |name|
  @mes_value = "a" * 5_242_880
  @records = [st_turn(name:, mes: @mes_value)]
end

Given(/\Athe file has a second turn record "(.*)" with mes "(.*)"\z/) do |name, mes|
  @records << st_turn(name:, mes:)
end

Then(/\Athe first unit's text equals the 5 MiB mes value byte for byte, with a bytesize of 5,242,880\z/) do
  st_assert(@units.first.text == @mes_value && @units.first.text.bytesize == 5_242_880, "first text bytesize #{@units.first.text.bytesize}")
end

Given(/\Aa session file whose first record is a system record with a String mes, followed by a turn record "(.*)"\z/) do |text|
  @records = [st_header.merge("mes" => "system text"), st_turn(mes: text)]
end

Given(/\Aa session file whose second record has a mes of two strings, each 600 KiB, whose join is over 1 MiB\z/) do
  @records = [st_turn(mes: "ok"), st_turn(mes: ["a" * 614_400, "b" * 614_400])]
end

Then(/\Athe second unit's text is the first string, one line break character, then the second string, byte for byte\z/) do
  st_assert(@units[1].text == @records[1]["mes"].join("\n"), "second text bytesize #{@units[1].text.bytesize}")
end

# Scenario: a file name with a line break. The feature text writes the break as \n; st_unescape makes it one character.
Given(/\Aa session file named "(.*)" whose records are the JSON array:\z/) do |name, doc|
  @file_name = st_unescape(name)
  @records = JSON.parse(doc).map { |partial| st_turn.merge(partial) }
end

Then(/\Ano warning is logged\z/) do
  st_assert(@logger.warnings.empty?, "#{@logger.warnings.size} warnings were logged")
end

Then(/\Aexactly (\d+) warnings? (?:is|are) logged, each with reason "(.*)"\z/) do |count, reason|
  st_assert(@logger.warnings.size == count.to_i, "#{@logger.warnings.size} warnings, expected #{count}")
  st_assert(@logger.warnings.all? { |warning| warning[:fields][:reason] == reason }, "a warning has a different reason")
end

Then(/\Athe warning fields include (\{.*\})\z/) do |literal|
  expected = JSON.parse(literal).transform_keys(&:to_sym)
  fields = @logger.warnings.last&.fetch(:fields, nil) || {}
  mismatch = expected.reject { |key, value| fields.key?(key) && fields[key] == value }
  st_assert(mismatch.empty?, "warning fields differ: #{mismatch}, actual #{fields}")
end

Then(/\Ano warning message or field contains a line break character\z/) do
  broken = @logger.warnings.select do |warning|
    [warning[:message], *warning[:fields].values].any? { |value| value.is_a?(String) && value.include?("\n") }
  end
  st_assert(broken.empty?, "a warning contains a line break: #{broken.inspect}")
end
