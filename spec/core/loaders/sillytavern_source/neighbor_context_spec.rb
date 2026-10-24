# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Core::Loaders::SillyTavernSource::NeighborContext do
  let(:records) do
    [
      { "name" => "Mason", "is_user" => true, "is_system" => false, "mes" => "secret text" },
      { "name" => "Steve", "is_user" => false, "is_system" => true },
      { "name" => "Robert", "is_user" => false, "is_system" => false },
    ]
  end

  it "reports first with a nil previous side for the first record" do
    expect(described_class.fields(records, 0)).to eq(
      position: "first", previous_name: nil, next_name: "Steve",
      previous_is_user: nil, next_is_user: false, previous_is_system: nil, next_is_system: true
    )
  end

  it "reports middle with both neighbours for a record between two others" do
    expect(described_class.fields(records, 1)).to eq(
      position: "middle", previous_name: "Mason", next_name: "Robert",
      previous_is_user: true, next_is_user: false, previous_is_system: false, next_is_system: false
    )
  end

  it "reports last with a nil next side for the last record" do
    expect(described_class.fields(records, 2)).to eq(
      position: "last", previous_name: "Steve", next_name: nil,
      previous_is_user: false, next_is_user: nil, previous_is_system: true, next_is_system: nil
    )
  end

  it "never includes message text" do
    expect(described_class.fields(records, 1).values).not_to include("secret text")
  end

  it "gives a non-String name as nil" do
    named = [{ "name" => { "x" => "y" }, "is_user" => false }, { "name" => "Steve" }]

    expect(described_class.fields(named, 1)[:previous_name]).to be_nil
  end

  it "reports first for a single record file" do
    expect(described_class.fields([records.first], 0)).to include(position: "first", previous_name: nil, next_name: nil)
  end

  describe "name sanitizing" do
    def name_of(name)
      described_class.fields([{ "name" => name }, { "name" => "Steve" }], 1)[:previous_name]
    end

    it "replaces a newline in a name with a single space" do
      expect(name_of("Mason\nFORGED level=error")).to eq("Mason FORGED level=error")
    end

    it "replaces a carriage return in a name with a space" do
      expect(name_of("Mason\r\nSteve")).to eq("Mason Steve")
    end

    it "replaces an ANSI escape introducer with a space" do
      expect(name_of("\e[31mMason\e[0m")).to eq("[31mMason [0m")
    end

    it "caps a name at 64 characters" do
      expect(name_of("a" * 100)).to eq("a" * 64)
    end

    it "gives nil for a name that is empty after sanitizing" do
      expect(name_of(" \n\t\e ")).to be_nil
    end

    it "strips after capping, so a capped name never ends in whitespace" do
      capped = name_of("#{'a' * 63} b")

      expect(capped).to eq("a" * 63)
      expect(capped).not_to end_with(" ")
    end
  end
end
