# frozen_string_literal: true

require "spec_helper"

RSpec.describe SFL::Store::DocumentArchive do
  subject(:archive) { described_class.new(db) }

  let(:db) { SFL::Store::StoreTestDb.db }
  let(:collection_id) { db[:collections].insert(name: "claude-chats") }
  let(:stamp) { Time.local(2026, 1, 2, 3, 4, 5) }

  before { SFL::Store::StoreTestDb.clean! }

  def seed(key, archived_at: nil)
    db[:documents].insert(collection_id:, document_key: key, source_path: "/x/#{key}.json",
      archived_at:, updated_at: stamp)
  end

  def row(key) = db[:documents].where(document_key: key).first

  describe "#archive" do
    it "sets archived_at to the current time and leaves updated_at alone" do
      seed("doc-a")
      before_time = Time.now
      expect(archive.archive("doc-a")).to eq(:archived)

      expect(row("doc-a")[:archived_at]).to be_between(before_time - 1, Time.now + 1)
      expect(row("doc-a")[:updated_at]).to eq(stamp)
    end

    it "keeps the original archived_at when the document is already archived" do
      seed("doc-a", archived_at: stamp)

      expect(archive.archive("doc-a")).to eq(:already_archived)
      expect(row("doc-a")).to include(archived_at: stamp, updated_at: stamp)
    end

    it "raises and changes no row for an unknown key" do
      seed("doc-a")

      expect { archive.archive("no-such-document") }
        .to raise_error(SFL::Store::Error, 'no document matched "no-such-document"')
      expect(row("doc-a")[:archived_at]).to be_nil
    end

    ["*", "%", "", "doc-%", "doc-*"].each do |key|
      it "treats #{key.inspect} as a literal key and matches nothing" do
        seed("doc-a")

        expect { archive.archive(key) }.to raise_error(SFL::Store::Error)
        expect(db[:documents].exclude(archived_at: nil).count).to eq(0)
      end
    end

    it "writes a key with a newline as one line in the error" do
      expect { archive.archive("a\nb") }.to raise_error(SFL::Store::Error, 'no document matched "a\\nb"')
    end
  end

  describe "#unarchive" do
    it "sets archived_at to null and leaves updated_at alone" do
      seed("doc-a", archived_at: stamp)

      expect(archive.unarchive("doc-a")).to eq(:unarchived)
      expect(row("doc-a")).to include(archived_at: nil, updated_at: stamp)
    end

    it "changes nothing when the document is not archived" do
      seed("doc-a")

      expect(archive.unarchive("doc-a")).to eq(:not_archived)
      expect(row("doc-a")).to include(archived_at: nil, updated_at: stamp)
    end

    it "raises for an unknown key" do
      expect { archive.unarchive("no-such-document") }.to raise_error(SFL::Store::Error, /no document matched/)
    end
  end
end
