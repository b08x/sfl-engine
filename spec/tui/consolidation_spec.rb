# frozen_string_literal: true

require "open3"
require "spec_helper"

# Facts 24, 35 and 36: the TUI runs on ratatui_ruby, the desktop GUI is
# gone, and the review collaborators it used are kept.
RSpec.describe "TUI consolidation" do # rubocop:disable RSpec/DescribeClass -- repository-level facts, not one class
  let(:root) { File.expand_path("../..", __dir__) }
  let(:gemfile) { File.read(File.join(root, "Gemfile")) }
  let(:lockfile) { File.read(File.join(root, "Gemfile.lock")) }

  def declared?(text, gem) = text.match?(/^\s*gem "#{gem}"/) || text.match?(/^    #{Regexp.escape(gem)} \(/)

  it "depends on ratatui_ruby and on none of bubbletea, bubbles, lipgloss or glamour (fact 24)" do
    expect(declared?(gemfile, "ratatui_ruby")).to be(true)
    %w[bubbletea bubbles lipgloss glamour].each do |gem|
      expect(declared?(gemfile, gem)).to be(false), "#{gem} still in Gemfile"
      expect(declared?(lockfile, gem)).to be(false), "#{gem} still in Gemfile.lock"
    end
  end

  it "has no desktop GUI, no GUI specs and no GUI gems (fact 35)" do
    %w[exe/sfl-review lib/sfl/gui spec/gui].each { |path| expect(File.exist?(File.join(root, path))).to be(false), path }
    %w[glimmer-dsl-libui libui].each do |gem|
      expect(declared?(gemfile, gem)).to be(false), "#{gem} still in Gemfile"
      expect(declared?(lockfile, gem)).to be(false), "#{gem} still in Gemfile.lock"
    end
    # fiddle stays in the lockfile only as a dependency of pycall and ruby-spacy.
    expect(declared?(gemfile, "fiddle")).to be(false)
    expect(lockfile[/^DEPENDENCIES\n(?:  .*\n)*/]).not_to match(/^  fiddle\b/)
    expect(SFL.const_defined?(:GUI, false)).to be(false)
  end

  it "keeps the review repositories, review types and clause review service (fact 36)" do
    expect(SFL::Store::PgReviewQueueRepository.public_instance_methods(false)).to contain_exactly(:enqueue, :find, :pending, :decide)
    expect(SFL::Store::PgAnnotationReviewRepository.public_instance_methods(false))
      .to contain_exactly(:record_review, :reviews_for, :review_queue)
    expect(SFL::Core::Types::ReviewQueueDecision.values).to eq(%w[approve edit reject])
    expect(SFL::Core::Types::ReviewDecision.values).to eq(%w[accepted rejected re_annotated])
    expect(SFL::API::ClauseReviewService.public_instance_methods(false)).to contain_exactly(:review)
  end

  describe "configuration and layout (facts 72 and 74)" do
    let(:code_files) do
      Dir.glob("{app,lib,exe,rakelib}/**/*", base: root).select { |path| File.file?(File.join(root, path)) } + %w[Rakefile config.ru boot.rb]
    end

    # A read is any ENV mention on a code line other than an assignment
    # (LLM::Tracing hands Langfuse its keys through ENV).
    def env_reads(path)
      File.readlines(File.join(root, path)).each_with_index.filter_map do |line, index|
        code = line.strip
        next if code.start_with?("#") || !code.match?(/\bENV\b/) || code.match?(/\AENV\[[^\]]+\]\s*=[^=]/)

        "#{path}:#{index + 1}"
      end
    end

    it "reads ENV only in SFL::Boot (fact 72)" do
      outside_boot = code_files.reject { |path| path == "lib/sfl/boot.rb" || path.start_with?("lib/sfl/boot/") }

      expect(outside_boot.flat_map { |path| env_reads(path) }).to eq([])
    end

    it "documents every SFL_* variable in .env.example (fact 72)" do
      example = File.read(File.join(root, ".env.example"))
      names = code_files.flat_map { |path| File.read(File.join(root, path)).scan(/\bSFL_[A-Z0-9_]*[A-Z0-9]\b/) }.uniq

      expect(names.reject { |name| example.include?(name) }).to eq([])
    end

    # New files are those added since the commit this goal started from,
    # plus files not yet committed.
    it "gives every new file under lib/ a spec at the matching path (fact 74)" do
      added, status = Open3.capture2("git", "-C", root, "diff", "--diff-filter=A", "--name-only", "7cf8e7f", "--", "lib")
      untracked, untracked_status = Open3.capture2("git", "-C", root, "ls-files", "--others", "--exclude-standard", "--", "lib")
      expect([status.success?, untracked_status.success?]).to eq([true, true]), "git diff/ls-files failed"

      new_files = (added.lines + untracked.lines).map(&:strip).grep(/\.rb\z/).uniq
      missing = new_files.reject { |path| File.exist?(File.join(root, path.sub(%r{\Alib/sfl/}, "spec/").sub(/\.rb\z/, "_spec.rb"))) }

      expect(missing).to eq([])
    end
  end
end
