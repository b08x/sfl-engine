# frozen_string_literal: true

namespace :eval do
  desc "Load the frozen narrative digests (items 1-14) into Langfuse dataset sfl-narrative-digests"
  task :build_narrative_dataset do
    require_relative "../lib/sfl"

    engine_output = File.expand_path("../output", __dir__)
    compiler_output = File.expand_path("../../sfl-compiler/output", __dir__)
    eval_dir = File.expand_path("../output/eval", __dir__)
    sources = SFL::Eval::NarrativeSources.catalog(engine_output:, compiler_output:, eval_dir:)

    client = SFL::Boot.langfuse_client
    result = SFL::Eval::NarrativeDatasetBuilder.new(client:, sources:).call
    puts "Loaded #{result.loaded.size} items; skipped #{result.skipped.size} (#{result.skipped.join(', ')})"
  end

  desc "Create the 5 score configs and the pass2-gold / judge-calibration annotation queues in Langfuse"
  task :setup_langfuse do
    require_relative "../lib/sfl"

    result = SFL::Eval::LangfuseSetup.new(client: SFL::Boot.langfuse_client).call
    puts "Score configs: #{result.configs.join(', ')}"
    puts "Queues: #{result.queues.join(', ')}"
    unless result.manual_steps.empty?
      puts "Manual steps required:"
      result.manual_steps.each { |step| puts "  - #{step}" }
    end
  end

  desc "Run Pass 2 (model from .env) on unseen conversations 11-14, writing output/eval/nd-<n>/"
  task :run_unseen do
    require "fileutils"
    require "open3"
    require_relative "../lib/sfl"

    workspace = File.expand_path("../..", __dir__)
    scratch = File.expand_path("../output/eval/_src", __dir__)
    FileUtils.mkdir_p(scratch)
    sources = SFL::Boot.eval_sources(workspace:)
    exports = sources.slice(:claude, :chatgpt, :mistral).transform_keys(&:to_s)
    exports["chatgpt"] = Dir[exports["chatgpt"]].first or abort("no ChatGPT export matches #{sources[:chatgpt]}")
    expanded = exports.to_h { |name, path| [name, SFL::Analysis::ChatExportExpander.expand(path, dest_dir: File.join(scratch, name))] }
    pick = -> (name, fragment) { expanded.fetch(name).find { |entry| entry[:path].end_with?("-#{fragment}.jsonl") }&.fetch(:path) or abort("no #{fragment} in #{name} export") }

    notebooklm = File.join(scratch, "nd-11.jsonl")
    SFL::Eval::NotebooklmConverter.call(sources.fetch(:notebooklm), notebooklm)
    inputs = {
      11 => notebooklm,
      12 => pick.call("claude", "c05dd4f6"),
      13 => pick.call("chatgpt", "6926a4c2"),
      14 => pick.call("mistral", "aca44f91"),
    }

    process_runner = lambda do |env, args, &block|
      status = nil
      Open3.popen2e(env, *args) do |_stdin, out, wait|
        block.call(out.each_line)
        status = wait.value
      end
      status
    end
    runner = SFL::Eval::UnseenRunner.new(logger: SFL::Boot.logger, process_runner:)

    # The Pass 2 model comes from SFL_TASK_PASS_TWO_ANNOTATION_* in .env (read by
    # SFL::Boot); this task sets no model of its own.
    inputs.each do |number, path|
      out_dir = File.expand_path("../output/eval/nd-#{number}", __dir__)
      report = File.join(out_dir, "conversation_analysis.json")
      if File.exist?(report)
        puts "nd-#{number}: report exists, skipping"
        next
      end
      result = runner.run_item(number:, input: path, out_dir:,
        command: [
          "bundle",
          "exec",
          File.expand_path("../exe/sfl-analyze", __dir__),
          "conversation",
          path,
          "--output-dir",
          out_dir,
          "--topics",
          "0",
])
      abort("nd-#{number} failed; see #{result[:log_path]}") unless result[:success]
    end
  end

  # The three analysis tasks below read the four unseen-conversation reports
  # that eval:run_unseen writes. Each report is one conversation. Fields read
  # (lib/sfl/formatters/json_formatter.rb, format_turns at line 123 and
  # format_clauses at line 148):
  #   turns[].turn_id                    (line 126)
  #   turns[].speaker                    (line 127)
  #   turns[].timestamp                  (line 128, ISO 8601 with offset)
  #   turns[].avg_tenor                  (line 130)
  #   turns[].tenor_shift                (line 133, nil on turn 1)
  #   turns[].semantic_coherence_score   (line 138, nil unless topics are enabled)
  #   turns[].clauses[].annotation_source (line 153)
  #   turns[].clauses[].process_type     (line 154, ideational payload)
  # The reports keep no speaker per clause in the same place;
  # the speaker comes from the turn, and the clause source is annotation_source.
  eval_report_labels = (11..14).map { |number| "output/eval/nd-#{number}/conversation_analysis.json" }
  eval_root = File.expand_path("..", __dir__)
  eval_out_dir = File.join(eval_root, "output", "eval")
  eval_turn_row = Struct.new(:turn_id, :speaker, :avg_tenor, :tenor_shift)

  eval_load_reports = lambda do
    require "json"
    missing = eval_report_labels.reject { |label| File.exist?(File.join(eval_root, label)) }
    abort("missing eval reports:\n  #{missing.join("\n  ")}\nrun eval:run_unseen first") unless missing.empty?

    eval_report_labels.map do |label|
      [label, JSON.parse(File.read(File.join(eval_root, label)))]
    rescue JSON::ParserError => e
      abort("#{label}: not valid JSON (#{e.message})")
    end
  end

  # Aborts naming the file and field when a turn lacks one of the keys.
  eval_turns = lambda do |label, report, fields|
    turns = report["turns"]
    abort("#{label}: missing required field turns") unless turns.is_a?(Array)
    turns.each do |turn|
      fields.each do |field|
        abort("#{label}: missing required field turns[].#{field}") unless turn.is_a?(Hash) && turn.key?(field)
      end
    end
    turns
  end

  eval_write = lambda do |name, rendered|
    require "fileutils"
    FileUtils.mkdir_p(eval_out_dir)
    File.write(File.join(eval_out_dir, "#{name}.md"), rendered[:markdown])
    File.write(File.join(eval_out_dir, "#{name}.json"), rendered[:json])
    puts "wrote output/eval/#{name}.md and output/eval/#{name}.json"
  end

  desc "Spearman correlation of avg_tenor vs semantic_coherence_score across nd-11..14 into output/eval/tenor_coherence.{md,json}"
  task :tenor_coherence do
    require_relative "../lib/sfl"

    reports = eval_load_reports.call
    rows = reports.flat_map do |label, report|
      eval_turns.call(label, report, %w[avg_tenor semantic_coherence_score]).map do |turn|
        { avg_tenor: turn["avg_tenor"], semantic_coherence_score: turn["semantic_coherence_score"] }
      end
    end
    result = SFL::Analysis::TenorCoherenceCorrelation.new(rows).call
    eval_write.call("tenor_coherence", SFL::Analysis::EvalReports.render(:tenor_coherence, result, sources: eval_report_labels))
  end

  desc "Process-type mix per speaker against the trusted-clause baseline across nd-11..14 into output/eval/process_mix.{md,json}"
  task :process_mix do
    require_relative "../lib/sfl"

    reports = eval_load_reports.call
    clause_fields = %w[annotation_source process_type]
    clauses = reports.flat_map do |label, report|
      eval_turns.call(label, report, %w[speaker clauses]).flat_map do |turn|
        turn["clauses"].map do |clause|
          clause_fields.each do |field|
            abort("#{label}: missing required field turns[].clauses[].#{field}") unless clause.is_a?(Hash) && clause.key?(field)
          end
          { speaker: turn["speaker"], process_type: clause["process_type"], source: clause["annotation_source"] }
        end
      end
    end
    result = SFL::Analysis::ProcessMixAnalyzer.new(clauses).call
    eval_write.call("process_mix", SFL::Analysis::EvalReports.render(:process_mix, result, sources: eval_report_labels))
  end

  desc "Tenor spikes after long pauses (GapAnalyzer) across nd-11..14 into output/eval/gap_analysis.{md,json}"
  task :gap_analysis do
    require "time"
    require_relative "../lib/sfl"

    reports = eval_load_reports.call
    conversations = reports.map do |label, report|
      turns = eval_turns.call(label, report, %w[turn_id timestamp avg_tenor tenor_shift speaker])
      turns.each do |turn|
        next if turn["turn_id"] <= 1 || !turn["tenor_shift"].nil?

        abort("#{label}: missing required field turns[].tenor_shift (turn_id #{turn['turn_id']})")
      end
      rows = turns.map do |turn|
        eval_turn_row.new(turn["turn_id"], turn["speaker"], turn["avg_tenor"], turn["tenor_shift"])
      end
      spike_ids = SFL::Analysis::TenorTracker.new(rows).detect_significant_shifts.to_set { |shift| shift[:turn_id] }
      {
        turns: turns.map do |turn|
          timestamp = begin
            Time.iso8601(turn["timestamp"])
          rescue ArgumentError, TypeError
            abort("#{label}: missing required field turns[].timestamp")
          end
          { timestamp:, spike: spike_ids.include?(turn["turn_id"]) }
        end,
      }
    end
    result = SFL::Analysis::GapAnalyzer.new(conversations).call
    eval_write.call("gap_analysis", SFL::Analysis::EvalReports.render(:gap_analysis, result, sources: eval_report_labels))
  end
end
