# frozen_string_literal: true

require "spec_helper"
require "digest"

RSpec.describe SFL::Core::Loaders::FileId do
  def ref(path, name: File.basename(path.to_s, ".*"))
    SFL::Core::Refs::FileRef.new(name:, extension: File.extname(path.to_s), content_identity: "0:0", size_bytes: 0,
      source_id: "root", path_hint: path)
  end

  # `module_function` keeps two copies of #call: the module method the loaders
  # call and the private instance method a mixin receives. Every example runs
  # through both, so each copy is pinned to the same behaviour.
  def file_id(file_ref)
    mixin = Object.new.extend(described_class).__send__(:call, file_ref)
    expect(described_class.call(file_ref)).to eq(mixin)
    mixin
  end

  it "joins the basename and the first 8 hex digits of the path's SHA-256" do
    expect(file_id(ref("/a/README.md")))
      .to eq("README-#{Digest::SHA256.hexdigest('/a/README.md')[0, 8]}")
  end

  it "gives two README.md files in different directories different ids" do
    expect(file_id(ref("/a/README.md"))).not_to eq(file_id(ref("/b/README.md")))
  end

  it "gives notes.md and notes.txt in one directory different ids" do
    expect(file_id(ref("/d/notes.md"))).not_to eq(file_id(ref("/d/notes.txt")))
  end

  it "gives the same path the same id every time" do
    first = file_id(ref("/a/README.md"))

    expect(file_id(ref("/a/README.md"))).to eq(first)
  end

  it "keeps the bare basename for a ref without a path" do
    expect(file_id(ref(nil, name: "notes"))).to eq("notes")
  end

  it "uses the ref's name rather than the path's basename" do
    expect(file_id(ref("/a/README.md", name: "Readme"))).to start_with("Readme-")
  end
end
