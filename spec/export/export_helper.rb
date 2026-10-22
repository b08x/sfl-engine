# frozen_string_literal: true

require_relative "../tui/spec_helper"

module ExportSpecSupport
  # Picks for the whole "papers" collection of TUISpecSupport, built the
  # way Browse builds them.
  def self.papers_picks
    state = TUISpecSupport.browse_state
    state.with(selection: state.selection.select(state.tree, "c:1")).picks
  end

  def self.records(picks = papers_picks) = SFL::Export::ClauseSelection.new(source: TUISpecSupport.source).resolve(picks)

  def self.golden(name) = File.read(File.expand_path("../fixtures/export/#{name}", __dir__))

  def self.write(writer, records)
    io = StringIO.new
    writer.call(records, io)
    io.string
  end
end
