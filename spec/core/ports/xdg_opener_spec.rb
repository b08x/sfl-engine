# frozen_string_literal: true

require "spec_helper"

# Fact 32: the open-viewer key runs xdg-open on the source file.
RSpec.describe SFL::Core::Ports::XdgOpener do
  it "spawns xdg-open on the path with output discarded and detaches it" do
    spawned = []
    detached = []
    opener = described_class.new(
      spawner: -> (*argv, **opts) { spawned << [argv, opts]; 4242 },
      detacher: -> (pid) { detached << pid }
    )

    opener.open("/data/figure.png")

    expect(spawned).to eq([[["xdg-open", "/data/figure.png"], { out: File::NULL, err: File::NULL }]])
    expect(detached).to eq([4242])
  end
end
