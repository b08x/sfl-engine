#!/usr/bin/env ruby
# frozen_string_literal: true

# Wall-clock + peak-RSS harness for the `sfl-analyze conversation`/`documentation` pipeline.
# Shells out to GNU `/usr/bin/time -v` around a CLI invocation and parses the resulting JSON
# report for clause/turn counts. Emits a YAML record to bench/results/, matching the perf-skill
# format: nothing is an "optimization" without a before/after pair of records like this one
# (track decision 5).
#
# IMPORTANT: run this FROM WITHIN the repo being benchmarked (`cd <repo> && ruby
# <path-to-this-file>/pipeline_bench.rb ...`), not from elsewhere with a --repo flag. This
# repo pins its Ruby via a local `.tool-versions`/`.ruby-version`; asdf's shims resolve that
# per-directory at invocation time, and a cross-directory subprocess spawn (chdir: option,
# Dir.chdir, even `bash -c "cd repo && ..."`) does not reliably carry that resolution into the
# child `bundle` process in this environment -- it silently re-resolves against the *caller's*
# global Ruby/gemset instead and fails with a misleading "not locally installed" error. Simplest
# fix: don't cross directories at all.
#
# Usage (from inside the target repo):
#   ruby /path/to/sfl-engine/bench/pipeline_bench.rb --subcommand conversation \
#     --input spec/fixtures/conversations/sample.jsonl --label legacy-baseline --pass1-only
#
# Deliberately does NOT default to a real (paid) LLM run: --pass1-only must be passed
# explicitly to skip it, and omitting it runs Pass 2 for real, at real API cost. Caller's
# choice, every time.

require "optparse"
require "json"
require "time"
require "fileutils"
require "tmpdir"
require "yaml"

RESULTS_DIR = File.expand_path("results", __dir__)

options = { topics: 3, pass1_only: false, subcommand: "conversation" }
OptionParser.new do |opts|
  opts.on("--subcommand CMD", "conversation|documentation") { |v| options[:subcommand] = v }
  opts.on("--input PATH", "Fixture path, relative to the current directory") { |v| options[:input] = v }
  opts.on("--label LABEL", "Record label, e.g. legacy-baseline") { |v| options[:label] = v }
  opts.on("--topics N", Integer, "Topic count for LDA") { |v| options[:topics] = v }
  opts.on("--pass1-only", "Skip Pass 2 (no LLM cost) -- must be passed explicitly") { options[:pass1_only] = true }
end.parse!

%i[input label].each do |key|
  next if options[key]

  warn "missing required --#{key}"
  exit 1
end

unless File.exist?("Gemfile") && File.exist?("exe/sfl-analyze")
  warn "run this from inside the repo being benchmarked (no Gemfile/exe/sfl-analyze in #{Dir.pwd})"
  exit 1
end

out_dir = Dir.mktmpdir("sfl_bench_")
time_log = "#{out_dir}/time.log"

cmd = [
  "/usr/bin/time",
  "-v",
  "-o",
  time_log,
  "bundle",
  "exec",
  "exe/sfl-analyze",
  options[:subcommand],
  options[:input],
  "--output-dir",
  out_dir,
  "--disable-tracing",
  "--topics",
  options[:topics].to_s,
]
cmd << "--pass1-only" if options[:pass1_only]

abort("sfl-analyze exited non-zero") unless system(*cmd)

report = JSON.parse(File.read("#{out_dir}/conversation_analysis.json"))
time_report = File.read(time_log)
elapsed_str = time_report[/Elapsed \(wall clock\) time.*?: ([\d:.]+)/, 1]
peak_rss_kb = time_report[/Maximum resident set size \(kbytes\): (\d+)/, 1].to_i

parts = elapsed_str.split(":").map(&:to_f)
elapsed_seconds = (parts.size == 3) ? (parts[0] * 3600) + (parts[1] * 60) + parts[2] : (parts[0] * 60) + parts[1]

clause_count = report.dig("metadata", "annotation_coverage", "total_clauses") || report.dig("metadata", "clause_count")
llm_calls = report.dig("metadata", "annotation_coverage", "llm")

record = {
  "label" => options[:label],
  "recorded_at" => Time.now.utc.iso8601,
  "repo" => Dir.pwd,
  "subcommand" => options[:subcommand],
  "input" => options[:input],
  "pass1_only" => options[:pass1_only],
  "elapsed_seconds" => elapsed_seconds.round(2),
  "peak_rss_mb" => (peak_rss_kb / 1024.0).round(1),
  "clause_count" => clause_count,
  "clauses_per_min" => clause_count ? (clause_count / (elapsed_seconds / 60.0)).round(1) : nil,
  "llm_calls" => llm_calls,
  "note" => "small fixture -- fixed process-boot cost (Ruby + spaCy/PyCall model load) " \
    "dominates elapsed time here; clauses_per_min is NOT a steady-state throughput number " \
    "until this is re-run against a production-shaped corpus per blueprint §4.1",
}

FileUtils.mkdir_p(RESULTS_DIR)
result_path = File.join(RESULTS_DIR, "#{options[:label]}-#{options[:subcommand]}.yml")
File.write(result_path, record.to_yaml)
FileUtils.rm_rf(out_dir)

puts "Wrote #{result_path}"
puts record.to_yaml
