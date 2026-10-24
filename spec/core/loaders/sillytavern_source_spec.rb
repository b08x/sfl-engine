# frozen_string_literal: true

require "spec_helper"
require "fileutils"
require "tmpdir"
require "json"

RSpec.describe SFL::Core::Loaders::SillyTavernSource do
  let(:dir) { Dir.mktmpdir }
  let(:logger) { instance_spy(SFL::Core::Ports::Logger) }
  let(:file_name) { "2024-6-15@18h35m15s.jsonl" }
  let(:system_header) do
    {
      "name" => "SillyTavern System",
      "is_user" => false,
      "is_system" => true,
      "is_group" => true,
      "mes" => "Group chat created...",
    }
  end

  after { FileUtils.rm_rf(dir) }

  def turn(**overrides)
    {
      "name" => "Steve",
      "is_user" => false,
      "is_system" => false,
      "send_date" => "June 15, 2024 6:35pm",
      "mes" => "hello",
    }.merge(overrides)
  end

  # Writes physical lines to a file in the tmp directory. Hashes are JSON-encoded; strings are raw lines.
  def write_session(lines, name: file_name)
    path = File.join(dir, name)
    body = lines.map { |line| line.is_a?(Hash) ? JSON.generate(line) : line }.join("\n")
    File.write(path, "#{body}\n")
    path
  end

  def load_units(path, file_id: "st-session", logger: self.logger)
    ref = file_ref(path)
    described_class.new(ref, file_id:, logger:).each_unit.to_a
  end

  describe "construction and enumeration" do
    it "is a Loaders::Source" do
      path = write_session([turn])

      expect(described_class.new(file_ref(path), file_id: "st-session")).to be_a(SFL::Core::Loaders::Source)
    end

    it "returns an Enumerator when no block is given" do
      path = write_session([turn])

      expect(described_class.new(file_ref(path), file_id: "st-session").each_unit).to be_a(Enumerator)
    end
  end

  describe "unit shape" do
    it "yields Types::Unit values with the contract fields" do
      path = write_session([turn(name: "Robert", is_user: true, mes: "hi there")])
      unit = load_units(path).first

      expect(unit).to be_a(SFL::Core::Types::Unit)
      expect(unit).to have_attributes(
        section_id: "st-session#turn-0", speaker: "Robert", is_user: true, text: "hi there",
        parent_section_id: nil, heading: nil, document_key: file_ref(path).path_hint,
        source_path: file_ref(path).path_hint
      )
    end

    it "sets metadata to the file_id and the source file basename" do
      path = write_session([turn])

      expect(load_units(path, file_id: "st-2").first.metadata).to eq(
        "file_id" => "st-2", "source_file" => file_name
      )
    end

    it "numbers section ids contiguously from turn-0 in file order" do
      path = write_session([turn(name: "Steve"), turn(name: "Mason"), turn(name: "Robert")])
      units = load_units(path)

      expect(units.map(&:section_id)).to eq(%w[st-session#turn-0 st-session#turn-1 st-session#turn-2])
      expect(units.map(&:speaker)).to eq(%w[Steve Mason Robert])
    end

    it "keeps the speaker from the name and is_user from the flag, not from each other" do
      path = write_session([turn(name: "Word Retrieval Unit", is_user: false)])

      expect(load_units(path).first).to have_attributes(speaker: "Word Retrieval Unit", is_user: false)
    end
  end

  describe "system records" do
    it "skips the header and any is_system record without a warning" do
      path = write_session([
        system_header,
        turn(mes: "one"),
        { "is_system" => true, "mes" => "note" },
        turn(mes: "two"),
        turn(mes: "three"),
])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(%w[one two three])
      expect(units.map(&:speaker)).to all(eq("Steve"))
      expect(logger).not_to have_received(:warn)
    end

    it "loads a file with no system record at all" do
      path = write_session([turn(mes: "a"), turn(mes: "b")])

      expect(load_units(path).size).to eq(2)
    end

    it "skips a String mes on a system record silently even when it is over 1 MiB" do
      path = write_session([system_header.merge("mes" => "s" * 1_048_577), turn(mes: "one")])
      units = nil

      expect { units = load_units(path, logger:) }.not_to raise_error
      expect(units.map(&:text)).to eq(%w[one])
      expect(logger).not_to have_received(:warn)
    end

    it "yields a non-system String mes of 1 MiB plus one byte whole" do
      message = "n" * 1_048_577
      units = load_units(write_session([system_header, turn(mes: message)]))

      expect(units.map(&:text)).to eq([message])
    end
  end

  describe "send_date as US Eastern wall-clock time" do
    # Expected UTC instants, covering EDT and EST days and the boundary days of 2024 and 2026.
    {
      "June 19, 2024 2:22pm" => "2024-06-19T18:22:00Z",
      "January 15, 2024 2:22pm" => "2024-01-15T19:22:00Z",
      "March 9, 2024 2:30am" => "2024-03-09T07:30:00Z",
      "March 10, 2024 1:59am" => "2024-03-10T06:59:00Z",
      "March 10, 2024 2:00am" => "2024-03-10T06:00:00Z",
      "March 10, 2024 3:00am" => "2024-03-10T07:00:00Z",
      "March 11, 2024 2:30am" => "2024-03-11T06:30:00Z",
      "March 3, 2024 12:00pm" => "2024-03-03T17:00:00Z",
      "March 8, 2026 12:00am" => "2026-03-08T05:00:00Z",
      "March 8, 2026 3:00am" => "2026-03-08T07:00:00Z",
      "November 2, 2024 12:00pm" => "2024-11-02T16:00:00Z",
      "November 3, 2024 12:59am" => "2024-11-03T04:59:00Z",
      "November 3, 2024 2:00am" => "2024-11-03T07:00:00Z",
      "November 4, 2024 12:00pm" => "2024-11-04T17:00:00Z",
      "November 1, 2026 12:30am" => "2026-11-01T04:30:00Z",
      "November 1, 2026 2:00am" => "2026-11-01T07:00:00Z",
      "June 19, 2024 12:05am" => "2024-06-19T04:05:00Z",
      "June 19, 2024 12:05pm" => "2024-06-19T16:05:00Z",
      "December 31, 2024 11:59pm" => "2025-01-01T04:59:00Z",
      "Sep 5, 2024 12:15am" => "2024-09-05T04:15:00Z",
    }.each do |send_date, expected|
      it "converts #{send_date.inspect} to #{expected}" do
        path = write_session([turn(send_date:)])
        sent_at = load_units(path, logger:).first.sent_at

        expect(sent_at.iso8601).to eq(expected)
        expect(sent_at.utc_offset).to eq(0)
        expect(logger).not_to have_received(:warn)
      end
    end

    it "does not take the file mtime as sent_at" do
      path = write_session([turn(send_date: "June 19, 2024 2:22pm")])
      File.utime(Time.utc(2026, 10, 24, 9), Time.utc(2026, 10, 24, 9), path)

      expect(load_units(path).first.sent_at).not_to eq(Time.utc(2026, 10, 24, 9))
    end

    it "shows the spring-forward jump: 1:59am EST to 3:00am EDT is 60 seconds" do
      path = write_session([turn(send_date: "March 10, 2024 1:59am"), turn(send_date: "March 10, 2024 3:00am")])
      units = load_units(path)

      expect(units.last.sent_at - units.first.sent_at).to eq(60)
    end

    it "shows the fall-back gap: 12:59am EDT to 2:00am EST is 7260 seconds" do
      path = write_session([turn(send_date: "November 3, 2024 12:59am"), turn(send_date: "November 3, 2024 2:00am")])
      units = load_units(path)

      expect(units.last.sent_at - units.first.sent_at).to eq(7260)
    end

    it "uses the second Sunday of March 2027 (March 14), so March 7 2027 is still EST" do
      path = write_session([turn(send_date: "March 7, 2027 12:00pm")])
      sent_at = load_units(path, logger:).first.sent_at

      expect(sent_at.iso8601).to eq("2027-03-07T17:00:00Z")
      expect(logger).not_to have_received(:warn)
    end
  end

  describe "unusable send_date" do
    {
      "yesterday" => "send_date_unparseable",
      "June 31, 2024 2:22pm" => "send_date_unparseable",
      "2024-06-19T14:22:00Z" => "send_date_unparseable",
      "" => "send_date_unparseable",
      "June 19, 2024 13:22pm" => "send_date_unparseable",
      "June 19, 2024 2:22pm\nlevel=error forged entry" => "send_date_unparseable",
    }.each do |send_date, reason|
      it "keeps the unit with sent_at nil and warns with reason #{reason} for #{send_date.inspect}" do
        path = write_session([turn(mes: "a"), turn(mes: "b", send_date:), turn(mes: "c")])
        units = load_units(path, logger:)

        expect(units.size).to eq(3)
        expect(units.map { |unit| unit.sent_at.nil? }).to eq([false, true, false])
        expect(logger).to have_received(:warn).once.with(
          satisfy { |message| !message.include?("forged") && !message.include?("yesterday") },
          component: "SillyTavernSource", file: file_name, line: 2, reason:
        )
      end
    end

    it "warns with send_date_missing when the key is absent" do
      record = turn(mes: "b")
      record.delete("send_date")
      path = write_session([turn, record])
      units = load_units(path, logger:)

      expect(units.last.sent_at).to be_nil
      expect(logger).to have_received(:warn).once.with(
        anything, component: "SillyTavernSource", file: file_name, line: 2, reason: "send_date_missing"
      )
    end

    it "treats a null send_date as missing" do
      path = write_session([turn(send_date: nil)])

      expect(load_units(path, logger:).first.sent_at).to be_nil
      expect(logger).to have_received(:warn).once.with(
        anything, component: "SillyTavernSource", file: file_name, line: 1, reason: "send_date_missing"
      )
    end

    it "takes no time from a valid-looking prefix of a crafted send_date" do
      crafted = "June 19, 2024 2:22pm\nlevel=error forged entry"
      path = write_session([turn(mes: "a"), turn(send_date: crafted), turn(mes: "c")])
      units = load_units(path, logger:)

      expect(units[1].sent_at).to be_nil
      expect(units[0].sent_at).to eq(Time.utc(2024, 6, 15, 22, 35))
      expect(units[2].sent_at).to eq(Time.utc(2024, 6, 15, 22, 35))
    end

    it "loads without a logger argument and without raising" do
      path = write_session([turn(send_date: "yesterday")])

      expect { described_class.new(file_ref(path), file_id: "st-session").each_unit.to_a }.not_to raise_error
    end
  end

  describe "line-delimited records" do
    it "raises when a raw U+0001 control character appears in the message" do
      raw_control = %({"name":"Steve","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:35pm",) +
        "\"mes\":\"ab\u0001cd\"}"
      path = write_session([turn(mes: "ok"), raw_control])

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::Error) { |error| expect(error.line).to eq(2) }
    end

    it "loads a message holding the \\n escape as one unit whose text contains the line break" do
      path = write_session([
        '{"name":"Hobbes","is_user":false,"is_system":false,"send_date":"June 15, 2024 6:35pm","mes":"First line\nsecond line"}',
        turn(name: "Steve", mes: "Next turn"),
      ])
      units = load_units(path)

      expect(units.map(&:text)).to eq(["First line\nsecond line", "Next turn"])
      expect(units.map(&:section_id)).to eq(%w[st-session#turn-0 st-session#turn-1])
    end

    it "loads the last record of a file with no trailing line break" do
      path = File.join(dir, file_name)
      File.write(path, [system_header, turn(mes: "first"), turn(mes: "last")].map { |record| JSON.generate(record) }.join("\n"))
      units = load_units(path)

      expect(units.map(&:text)).to eq(%w[first last])
      expect(units.last.section_id).to eq("st-session#turn-1")
    end

    it "raises naming the file and the physical line for a line that is not valid JSON, with no units" do
      path = write_session([turn(mes: "one"), '{"name":"Steve","mes":"open', turn(mes: "three")])
      yielded = []
      error = nil

      expect { described_class.new(file_ref(path), file_id: "st-session").each_unit { |unit| yielded << unit } }
        .to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError) { |raised| error = raised }

      expect(error).to have_attributes(message: "#{file_name}: Line 2 is not valid JSON", file: file_name, line: 2)
      expect(yielded).to be_empty
    end
  end

  describe "message size" do
    it "yields a message of 5 MiB whole, with its full text" do
      message = "a" * 5_242_880
      units = load_units(write_session([turn(mes: message), turn(mes: "after")]))

      expect(units.map { |unit| unit.text.bytesize }).to eq([5_242_880, 5])
      expect(units.first.text).to eq(message)
    end

    it "yields a 1 MiB message whose JSON form is larger because of escaped quotes" do
      message = '"' * 1_048_576
      units = load_units(write_session([turn(mes: message)]))

      expect(JSON.generate(turn(mes: message)).bytesize).to be > 1_048_576
      expect(units.map(&:text)).to eq([message])
    end

    it "yields a message of six-byte escapes whole" do
      message = "\u0001" * 1_048_576
      units = load_units(write_session([turn(mes: message)]))

      expect(units.map(&:text)).to eq([message])
    end
  end

  describe "markup and content as data" do
    it "emits markup, a code fence and a URL verbatim" do
      mes = "<b>bold</b> ```ruby\nputs 1\n``` *action* https://example.invalid/x?y=1"
      path = write_session([turn(mes:)])

      expect(load_units(path, logger:).first.text).to eq(mes)
      expect(logger).not_to have_received(:warn)
    end
  end

  describe "fatal file-level cases" do
    it "raises for a .json ref and yields nothing" do
      path = write_session([turn], name: "session.json")

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::Error) { |error| expect(error.file).to eq("session.json") }
    end

    it "raises for an empty file, naming the file" do
      path = write_session([], name: file_name)
      File.write(path, "")

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::Error, /#{Regexp.escape(file_name)}/)
    end

    it "raises for a header-only file" do
      path = write_session([system_header])

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::Error, /#{Regexp.escape(file_name)}/)
    end
  end

  describe "file names" do
    ["Branch #210 - 2024-6-19@16h23m07s.jsonl", "existential docker - 2024-6-19@16h55m50s.jsonl"].each do |name|
      it "loads #{name.inspect} and records it as source_file" do
        path = write_session([turn(mes: "a"), turn(mes: "b")], name:)
        units = load_units(path)

        expect(units.size).to eq(2)
        expect(units.map { |unit| unit.metadata["source_file"] }).to all(eq(name))
      end
    end

    context "when the basename contains a line break" do
      let(:name) { "bad\nname.jsonl" }

      it "logs warning fields and metadata with the line break made a space" do
        path = write_session([turn(mes: "a"), turn(name: "Robert", mes: nil)], name:)
        units = load_units(path, logger:)

        expect(units.map { |unit| unit.metadata["source_file"] }).to all(eq("bad name.jsonl"))
        expect(logger).to have_received(:warn).once.with(
          "mes missing, record skipped",
          component: "SillyTavernSource", file: "bad name.jsonl", line: 2, reason: "mes_missing", position: "last",
          previous_name: "Steve", next_name: nil, previous_is_user: false, next_is_user: nil,
          previous_is_system: false, next_is_system: nil
        )
      end

      it "raises a SourceError whose message and file hold no line break" do
        path = write_session(["not json"], name:)

        expect { load_units(path) }.to raise_error(SFL::Core::Loaders::Error) { |error|
          expect(error.message).to eq("bad name.jsonl: Line 1 is not valid JSON")
          expect(error.file).to eq("bad name.jsonl")
          expect(error.message).not_to include("\n")
        }
      end
    end
  end

  describe "blank lines between records" do
    it "skips an empty line between records without skipping the record after it" do
      path = write_session([turn(mes: "a"), "", turn(mes: "b")])
      units = load_units(path)

      expect(units.map(&:text)).to eq(%w[a b])
      expect(units.map(&:section_id)).to eq(%w[st-session#turn-0 st-session#turn-1])
    end

    it "skips whitespace-only lines between records" do
      path = write_session(["  \t ", turn(mes: "a"), "   ", turn(mes: "b")])

      expect(load_units(path).map(&:text)).to eq(%w[a b])
    end
  end

  describe "record shape" do
    def expect_not_a_message(path, line)
      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError) do |error|
        expect(error.message).to eq("#{file_name}: Record at line #{line} is not a message")
        expect(error.line).to eq(line)
      end
    end

    it "names the physical line of a JSON array record that is not a message" do
      expect_not_a_message(write_session([turn(mes: "one"), "[1]"]), 2)
    end

    it "names the physical line of a bare JSON scalar record that is not a message" do
      expect_not_a_message(write_session([turn(mes: "one"), "42"]), 2)
    end

    it "emits an empty speaker and is_user false when the name and is_user keys are absent" do
      record = turn(mes: "a")
      record.delete("name")
      record.delete("is_user")
      unit = load_units(write_session([record])).first

      expect(unit).to have_attributes(speaker: "", is_user: false, text: "a")
    end

    it "keeps a record whose is_system is the string true, and a record with no is_system key" do
      without_flag = turn(mes: "b")
      without_flag.delete("is_system")
      path = write_session([turn(mes: "a", is_system: "true"), without_flag])

      expect(load_units(path).map(&:text)).to eq(%w[a b])
    end
  end

  describe "non-String mes" do
    it "joins the two strings of an array mes with a newline" do
      units = load_units(write_session([turn(mes: ["first part", "second part"])]))

      expect(units.map(&:text)).to eq(["first part\nsecond part"])
    end

    it "extracts the string nested under a key of a hash mes and ignores the keys" do
      units = load_units(write_session([turn(mes: { "outer" => { "inner" => "nested text" }, "count" => 2 })]))

      expect(units.map(&:text)).to eq(["nested text"])
    end

    it "strips surrounding whitespace from the joined text of a non-String mes" do
      units = load_units(write_session([turn(mes: ["  padded  "])]))

      expect(units.map(&:text)).to eq(["padded"])
    end

    it "keeps an emoji inside a String mes unchanged" do
      units = load_units(write_session([turn(mes: "ok 🎉 done")]), logger:)

      expect(units.map(&:text)).to eq(["ok 🎉 done"])
      expect(logger).not_to have_received(:warn)
    end

    it "warns with mes_no_text and skips a number mes, with the neighbour context" do
      path = write_session([turn(name: "Steve", mes: "one"), turn(name: "Mason", mes: 42), turn(name: "Robert", mes: "three")])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(%w[one three])
      expect(logger).to have_received(:warn).once.with(
        "mes has no text, record skipped",
        component: "SillyTavernSource", file: file_name, line: 2, reason: "mes_no_text", position: "middle",
        previous_name: "Steve", next_name: "Robert", previous_is_user: false, next_is_user: false,
        previous_is_system: false, next_is_system: false
      )
    end

    it "warns with mes_no_text and skips an empty array" do
      units = load_units(write_session([turn(mes: "one"), turn(mes: []), turn(mes: "three")]), logger:)

      expect(units.map(&:text)).to eq(%w[one three])
      expect(logger).to have_received(:warn).once.with(
        "mes has no text, record skipped",
        component: "SillyTavernSource", file: file_name, line: 2, reason: "mes_no_text", position: "middle",
        previous_name: "Steve", next_name: "Steve", previous_is_user: false, next_is_user: false,
        previous_is_system: false, next_is_system: false
      )
    end

    it "yields the text of a non-String mes on a system record and keeps the system String record silent" do
      system_array = { "name" => "SillyTavern System", "is_user" => false, "is_system" => true, "send_date" => "June 15, 2024 6:35pm", "mes" => %w[Group created] }
      path = write_session([system_array, system_header, turn(mes: "one")])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(%W[Group\ncreated one])
      expect(units.map(&:section_id)).to eq(%w[st-session#turn-0 st-session#turn-1])
      expect(logger).not_to have_received(:warn)
    end

    it "yields extracted text over 1 MiB whole, joined by one newline" do
      units = load_units(write_session([turn(mes: ["ok"]), turn(mes: ["a" * 1_048_576, "b"])]))

      expect(units.map { |unit| unit.text.bytesize }).to eq([2, 1_048_576 + 1 + 1])
    end
  end

  describe "missing mes" do
    it "warns with mes_missing and the neighbour context, skips the record, and yields the later records" do
      path = write_session([
        turn(name: "Mason", is_user: true, mes: "one"),
        { "name" => "Robert", "is_user" => false, "is_system" => false },
        turn(name: "Steve", mes: "three"),
])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(%w[one three])
      expect(units.map(&:section_id)).to eq(%w[st-session#turn-0 st-session#turn-1])
      expect(logger).to have_received(:warn).once.with(
        "mes missing, record skipped",
        component: "SillyTavernSource", file: file_name, line: 2, reason: "mes_missing", position: "middle",
        previous_name: "Mason", next_name: "Steve", previous_is_user: true, next_is_user: false,
        previous_is_system: false, next_is_system: false
      )
    end

    it "treats a null mes as missing" do
      path = write_session([turn(mes: "one"), turn(mes: nil), turn(mes: "three")])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(%w[one three])
      expect(logger).to have_received(:warn).once.with(
        "mes missing, record skipped",
        component: "SillyTavernSource", file: file_name, line: 2, reason: "mes_missing", position: "middle",
        previous_name: "Steve", next_name: "Steve", previous_is_user: false, next_is_user: false,
        previous_is_system: false, next_is_system: false
      )
    end

    it "gives nil previous fields for a missing mes on the first record" do
      path = write_session([{ "name" => "Robert", "is_user" => true, "is_system" => false }, turn(name: "Steve", mes: "two")])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(["two"])
      expect(logger).to have_received(:warn).once.with(
        "mes missing, record skipped",
        component: "SillyTavernSource", file: file_name, line: 1, reason: "mes_missing", position: "first",
        previous_name: nil, next_name: "Steve", previous_is_user: nil, next_is_user: false,
        previous_is_system: nil, next_is_system: false
      )
    end

    it "gives nil next fields for a missing mes on the last record" do
      path = write_session([turn(name: "Steve", mes: "one"), { "name" => "Robert", "is_user" => true, "is_system" => false }])
      units = load_units(path, logger:)

      expect(units.map(&:text)).to eq(["one"])
      expect(logger).to have_received(:warn).once.with(
        "mes missing, record skipped",
        component: "SillyTavernSource", file: file_name, line: 2, reason: "mes_missing", position: "last",
        previous_name: "Steve", next_name: nil, previous_is_user: false, next_is_user: nil,
        previous_is_system: false, next_is_system: nil
      )
    end

    it "raises no-turns when every record is skipped" do
      expect { load_units(write_session([{ "name" => "Steve", "is_user" => false, "is_system" => false }])) }
        .to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError, "#{file_name}: No session turns")
    end
  end

  describe "enumerator laziness" do
    it "returns a lazy enumerator: a fatal error surfaces when the enumerator is consumed, not when it is created" do
      path = write_session([turn, '{"name":"Steve","mes":"open', "still open"])
      enumerator = described_class.new(file_ref(path), file_id: "st-session").each_unit

      expect { enumerator.to_a }.to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError)
    end
  end

  describe "send_date edge values" do
    it "converts an uppercase full month name" do
      path = write_session([turn(send_date: "JUNE 19, 2024 2:22pm")])

      expect(load_units(path, logger:).first.sent_at.iso8601).to eq("2024-06-19T18:22:00Z")
      expect(logger).not_to have_received(:warn)
    end

    it "converts an uppercase abbreviated month name" do
      path = write_session([turn(send_date: "SEP 5, 2024 12:15am")])

      expect(load_units(path, logger:).first.sent_at.iso8601).to eq("2024-09-05T04:15:00Z")
      expect(logger).not_to have_received(:warn)
    end

    it "treats 2:59am on the spring-forward day as EDT, because the switch happens at 2:00 local time" do
      path = write_session([turn(send_date: "March 10, 2024 2:59am")])

      expect(load_units(path, logger:).first.sent_at.iso8601).to eq("2024-03-10T06:59:00Z")
    end

    it "treats 1:59am on the fall-back day as EDT, because the switch happens at 2:00 local time" do
      path = write_session([turn(send_date: "November 3, 2024 1:59am")])

      expect(load_units(path, logger:).first.sent_at.iso8601).to eq("2024-11-03T05:59:00Z")
    end

    {
      "June 19, 2024 2:60pm" => "minute 60",
      "June 19, 2024 0:22pm" => "hour 0 on a 12-hour clock",
    }.each_key do |send_date|
      it "treats #{send_date.inspect} as unparseable and keeps the unit with sent_at nil" do
        path = write_session([turn(mes: "a"), turn(mes: "b", send_date:), turn(mes: "c")])
        units = load_units(path, logger:)

        expect(units.map { |unit| unit.sent_at.nil? }).to eq([false, true, false])
        expect(logger).to have_received(:warn).once.with(
          anything, component: "SillyTavernSource", file: file_name, line: 2, reason: "send_date_unparseable"
        )
      end
    end

    it "treats a non-string send_date as unparseable" do
      path = write_session([turn(send_date: 12_345)])

      expect(load_units(path, logger:).first.sent_at).to be_nil
      expect(logger).to have_received(:warn).once.with(
        anything, component: "SillyTavernSource", file: file_name, line: 1, reason: "send_date_unparseable"
      )
    end

    it "logs the fixed warning text, with the line and reason as keyword fields" do
      path = write_session([turn(mes: "a"), turn(mes: "b", send_date: "yesterday")])
      load_units(path, logger:)

      expect(logger).to have_received(:warn).once.with(
        "send_date unusable, sent_at left nil",
        component: "SillyTavernSource", file: file_name, line: 2, reason: "send_date_unparseable"
      )
    end
  end

  describe "file-level fatal errors with exact messages" do
    it "names the file in the message for an unsupported extension" do
      path = write_session([turn], name: "session.json")

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError) do |error|
        expect(error.message).to eq("session.json: Unsupported session format: expected a .jsonl ref")
        expect(error.line).to be_nil
      end
    end

    it "uses the exact no-turns message for a header-only file" do
      path = write_session([system_header])

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError) do |error|
        expect(error.message).to eq("#{file_name}: No session turns")
        expect(error.line).to be_nil
      end
    end

    it "uses the exact no-turns message for an empty file" do
      path = write_session([], name: file_name)
      File.write(path, "")

      expect { load_units(path) }.to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError) do |error|
        expect(error.message).to eq("#{file_name}: No session turns")
      end
    end

    it "rejects a file that is not valid UTF-8 before yielding any unit" do
      path = File.join(dir, file_name)
      File.binwrite(path, "#{JSON.generate(turn(mes: 'a'))}\n#{"\xFF\n".b}")
      yielded = []

      expect do
        described_class.new(file_ref(path), file_id: "st-session").each_unit { |unit| yielded << unit }
      end.to raise_error(SFL::Core::Loaders::SillyTavernSource::SourceError) { |error| expect(error.message).to eq("#{file_name}: Session is not valid UTF-8") }
      expect(yielded).to be_empty
    end

    it "raises a SourceError, not a TypeError, for a ref with no path hint" do
      ref = instance_double(SFL::Core::Refs::FileRef, extension: ".json", path_hint: nil)

      expect { described_class.new(ref, file_id: "st-session").each_unit.to_a }.to raise_error(
        SFL::Core::Loaders::SillyTavernSource::SourceError, ": Unsupported session format: expected a .jsonl ref"
      )
    end

    it "defaults the line of a SourceError to nil when none is given" do
      error = SFL::Core::Loaders::SillyTavernSource::SourceError.new("boom", file: "x.jsonl")

      expect(error).to have_attributes(message: "boom", file: "x.jsonl", line: nil)
    end
  end
end
