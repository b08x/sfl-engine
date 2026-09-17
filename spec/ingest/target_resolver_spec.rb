# frozen_string_literal: true

require "tmpdir"

RSpec.describe SFL::Ingest::TargetResolver do
  describe ".call" do
    it "returns {type: :git, repo:, ref:} for SCP-style git remote" do
      result = described_class.call("git@github.com:b08x/dots.git")
      expect(result).to eq({ type: :git, repo: "git@github.com:b08x/dots.git", ref: "HEAD" })
    end

    it "returns {type: :git, repo:, ref:} for https URL ending .git" do
      result = described_class.call("https://github.com/b08x/dots.git")
      expect(result).to eq({ type: :git, repo: "https://github.com/b08x/dots.git", ref: "HEAD" })
    end

    it "returns {type: :git, repo:, ref:} for https URL on a known forge host" do
      result = described_class.call("https://gitlab.com/group/project")
      expect(result).to eq({ type: :git, repo: "https://gitlab.com/group/project", ref: "HEAD" })
    end

    it "returns {type: :filesystem, root:} for a file:// URL" do
      result = described_class.call("file:///tmp/some-repo")
      expect(result).to eq({ type: :filesystem, root: "/tmp/some-repo" })
    end

    it "returns {type: :git, repo:, ref:} when a .git dir exists at the path" do
      Dir.mktmpdir do |dir|
        git_dir = File.join(dir, ".git")
        Dir.mkdir(git_dir)
        result = described_class.call(dir)
        expect(result).to eq({ type: :git, repo: dir, ref: "HEAD" })
      end
    end

    it "returns {type: :filesystem, root:} for a directory" do
      Dir.mktmpdir do |dir|
        result = described_class.call(dir)
        expect(result).to eq({ type: :filesystem, root: dir })
      end
    end

    it "returns {type: :filesystem, root:} for a file" do
      Tempfile.create do |f|
        result = described_class.call(f.path)
        expect(result).to eq({ type: :filesystem, root: f.path })
      end
    end
  end

  describe "rule order — first match wins" do
    it "prefers SCP git remote over directory (git@… with : before path)" do
      # git@host:path is not a filesystem path, so SCP rule fires first
      result = described_class.call("git@example.com:repo")
      expect(result[:type]).to eq(:git)
    end
  end

  describe "~ expansion" do
    it "expands ~ once for a directory" do
      Dir.mktmpdir do |dir|
        # Create a symlink in home dir for testing
        home = ENV["HOME"]
        link = File.join(home, ".sfl_test_target_resolver_#{Process.pid}")
        FileUtils.ln_s(dir, link, force: true)
        begin
          result = described_class.call("~/.sfl_test_target_resolver_#{Process.pid}")
          expect(result).to eq({ type: :filesystem, root: dir })
        ensure
          FileUtils.rm_f(link)
        end
      end
    end
  end

  describe "unresolvable targets" do
    it "raises UnresolvableTarget for an https URL that is not a git remote" do
      expect { described_class.call("https://docs.example.com/usage") }.to raise_error(
        SFL::Ingest::TargetResolver::UnresolvableTarget, /not supported/
      )
    end

    it "names the rules tried in the error message" do
      expect { described_class.call("https://docs.example.com/usage") }.to raise_error(
        SFL::Ingest::TargetResolver::UnresolvableTarget, /scp git remote.*https git URL.*file:\/\/ URL.*\.git directory.*directory.*file/
      )
    end

    it "does not mention ENOENT in the error message" do
      expect { described_class.call("https://docs.example.com/usage") }.not_to raise_error(
        SFL::Ingest::TargetResolver::UnresolvableTarget, /ENOENT/
      )
    end
  end

  describe "UnresolvableTarget" do
    it "subclasses ArgumentError" do
      expect(SFL::Ingest::TargetResolver::UnresolvableTarget).to be < ArgumentError
    end
  end

  describe "no forbidden calls in the file" do
    it "contains no Dir.glob, File.read, net/http, or ENV" do
      source = File.read("lib/sfl/ingest/target_resolver.rb")
      expect(source).not_to include("Dir.glob")
      expect(source).not_to include("File.read")
      expect(source).not_to include("net/http")
      expect(source).not_to match(/\bENV\b/)
    end
  end
end
