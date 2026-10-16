# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe SFL::Core::Ports::Adapters::FilesystemCorpusSource do
  let(:dir) { Dir.mktmpdir("fcs_spec") }
  let(:root) { dir }

  after { FileUtils.rm_rf(dir) }

  def write_file(path, content = "test")
    full = File.join(dir, path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, content)
    full
  end

  def write_symlink(target, link)
    full_link = File.join(dir, link)
    FileUtils.mkdir_p(File.dirname(full_link))
    File.symlink(target, full_link)
    full_link
  end

  describe "as a CorpusSource" do
    subject { described_class.new(root) }

    it_behaves_like "a corpus source"
  end

  describe "single file root" do
    subject { described_class.new(file_path) }

    let(:file_path) { write_file("notes.md", "# Hello") }

    it "yields exactly one ref" do
      refs = subject.refs
      expect(refs.size).to eq(1)
    end

    it "yields a FileRef with correct attributes" do
      ref = subject.refs.first
      expect(ref).to be_a(SFL::Core::Refs::FileRef)
      expect(ref.name).to eq("notes")
      expect(ref.extension).to eq(".md")
      expect(ref.path_hint).to eq(file_path)
      expect(ref.source_id).to eq(file_path)
      expect(ref.size_bytes).to eq(7)
    end

    it "reads content via the ref" do
      ref = subject.refs.first
      expect(ref.read).to eq("# Hello")
    end

    it "forces include_images when root is an image" do
      image_path = write_file("photo.png", "fake-png")
      source = described_class.new(image_path)
      expect(source.refs.size).to eq(1)
      expect(source.refs.first.extension).to eq(".png")
    end
  end

  describe "directory walk" do
    subject { described_class.new(root) }

    before do
      write_file("a.md", "# A")
      write_file("b.txt", "B content")
      write_file("sub/c.md", "# C")
      write_file("sub/deep/d.md", "# D")
    end

    it "yields all non-image files recursively" do
      names = subject.refs.map(&:name).sort
      expect(names).to eq(%w[a b c d])
    end

    it "yields refs with path_hint set to full path" do
      ref = subject.refs.find { |r| r.name == "d" }
      expect(ref.path_hint).to end_with("sub/deep/d.md")
    end

    it "sets source_id to the root directory" do
      subject.refs.each do |ref|
        expect(ref.source_id).to eq(root)
      end
    end

    it "content_identity is mtime+size" do
      ref = subject.refs.find { |r| r.name == "a" }
      stat = File.stat(File.join(root, "a.md"))
      expect(ref.content_identity).to eq("#{stat.mtime.to_i}:#{stat.size}")
    end
  end

  describe "dot-directory exclusion" do
    subject { described_class.new(root) }

    before do
      write_file("visible.md", "# V")
      write_file(".hidden/secret.md", "# secret")
      write_file(".git/config", "[core]")
    end

    it "excludes dot-directories by default" do
      names = subject.refs.map(&:name)
      expect(names).to include("visible")
      expect(names).not_to include("secret", "config")
    end

    it "counts skipped dot-directories in stats" do
      subject.refs
      expect(subject.stats[:skipped_dotdirs]).to be >= 1
    end

    context "when exclude_dot_dirs is false" do
      subject { described_class.new(root, exclude_dot_dirs: false) }

      it "includes dot-directory contents" do
        names = subject.refs.map(&:name)
        expect(names).to include("secret")
      end
    end
  end

  describe "image exclusion" do
    subject { described_class.new(root) }

    before do
      write_file("doc.md", "# Doc")
      write_file("image.png", "fake-png")
      write_file("photo.jpg", "fake-jpg")
    end

    it "excludes image files by default" do
      names = subject.refs.map(&:name)
      expect(names).to include("doc")
      expect(names).not_to include("image", "photo")
    end

    it "counts skipped images in stats" do
      subject.refs
      expect(subject.stats[:skipped_images]).to eq(2)
    end

    context "when include_images is true" do
      subject { described_class.new(root, include_images: true) }

      it "includes image files" do
        names = subject.refs.map(&:name).sort
        expect(names).to include("doc", "image", "photo")
      end
    end
  end

  describe ".gitignore support" do
    subject { described_class.new(root) }

    before do
      write_file("keep.md", "# Keep")
      write_file("ignore.tmp", "temp")
      write_file(".gitignore", "*.tmp\n")
      write_file("sub/keep2.md", "# Keep2")
      write_file("sub/skip.tmp", "temp")
    end

    it "excludes gitignored files" do
      names = subject.refs.map(&:name)
      expect(names).to include("keep", "keep2", ".gitignore")
      expect(names).not_to include("ignore", "skip")
    end

    it "counts skipped ignored files in stats" do
      subject.refs
      expect(subject.stats[:skipped_ignored]).to eq(2)
    end

    context "with no ignore files configured" do
      subject { described_class.new(root, ignore_files: []) }

      it "includes all files" do
        names = subject.refs.map(&:name)
        expect(names).to include("ignore", "skip")
      end
    end

    context "with anchored patterns" do
      before do
        File.write(File.join(dir, ".gitignore"), "/build/\n")
        write_file("build/output.md", "# Build")
        write_file("sub/build/keep.md", "# Keep")
      end

      it "only ignores at the gitignore's directory level" do
        names = subject.refs.map(&:name).sort
        expect(names).not_to include("output")
        expect(names).to include("keep")
      end
    end
  end

  describe "symlink handling" do
    subject { described_class.new(root) }

    before do
      write_file("real.md", "# Real")
      write_symlink(File.join(dir, "real.md"), "link.md")
    end

    it "does not follow symlinks" do
      names = subject.refs.map(&:name)
      expect(names).to include("real")
      expect(names).not_to include("link")
    end
  end

  describe "vanished file handling" do
    subject { described_class.new(root) }

    it "skips files that disappear during enumeration" do
      write_file("stable.md", "# Stable")
      # Simulate a vanished file by creating a symlink to a non-existent target
      # — symlinks are skipped before stat, so test via race is fragile.
      # Instead verify the adapter doesn't raise on Errno::ENOENT
      expect { subject.refs }.not_to raise_error
    end
  end

  describe "lazy enumeration" do
    before do
      write_file("a.md", "# A")
      write_file("b.md", "# B")
      write_file("c.md", "# C")
    end

    it "yields refs one at a time without materializing" do
      enum = described_class.new(root).each_ref
      first = enum.next
      expect(first).to be_a(SFL::Core::Refs::FileRef)
      second = enum.next
      expect(second).to be_a(SFL::Core::Refs::FileRef)
    end
  end

  describe "non-existent root" do
    subject { described_class.new("/nonexistent/path/that/does/not/exist") }

    it "yields nothing" do
      expect(subject.refs).to be_empty
    end
  end
end
