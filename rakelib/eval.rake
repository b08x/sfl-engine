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

    # The Pass 2 model comes from SFL_TASK_PASS_TWO_ANNOTATION_* in .env (read by
    # SFL::Boot); this task sets no model of its own.
    inputs.each do |number, path|
      out_dir = File.expand_path("../output/eval/nd-#{number}", __dir__)
      report = File.join(out_dir, "conversation_analysis.json")
      if File.exist?(report)
        puts "nd-#{number}: report exists, skipping"
        next
      end
      puts "nd-#{number}: Pass 2 on #{File.basename(path)}"
      FileUtils.mkdir_p(out_dir)
      log_path = File.join(out_dir, "run.log")
      File.write(log_path, "")
      turns = 0
      status = nil
      Open3.popen2e("bundle", "exec", File.expand_path("../exe/sfl-analyze", __dir__),
        "conversation", path, "--output-dir", out_dir) do |_stdin, out, wait|
        out.each_line do |line|
          File.write(log_path, line, mode: "a")
          turns += 1 if line.include?("pass_one completed")
          puts "  nd-#{number}: #{turns} turns processed" if line.include?("pass_one completed") && (turns % 10).zero?
          puts "  #{line}" if line.match?(/WARN|ERROR|fallback/)
        end
        status = wait.value
      end
      puts "nd-#{number}: finished, #{turns} turns, exit #{status.exitstatus}"
      abort("nd-#{number} failed; see #{log_path}") unless status.success?
    end
  end
end
