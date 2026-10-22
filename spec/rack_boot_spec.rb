# frozen_string_literal: true

require "open3"
require "rbconfig"

# Loads the repo-root boot.rb (required by config.ru) in a child process.
# The child stops at SFL::DockerServices.ensure_running!, because the steps
# after it need the mail gem and the spaCy sidecar, which the suite lacks.
# The probe calls the real method, so a missing `enabled:` keyword raises
# ArgumentError and the child exits non-zero.
RSpec.describe "boot.rb (rack boot)" do # rubocop:disable RSpec/DescribeClass -- a repo-root script, not a class
  let(:root) { File.expand_path("..", __dir__) }

  let(:probe) do
    <<~RUBY
      require #{File.join(root, 'lib/sfl').inspect}
      SFL::DockerServices.singleton_class.prepend(Module.new do
        def ensure_running!(**kwargs)
          puts "enabled=\#{kwargs.fetch(:enabled, :missing)}"
          super(**kwargs, command: ->(*) { false })
          $stdout.flush
          exit!(0)
        end
      end)
      require #{File.join(root, 'boot').inspect}
    RUBY
  end

  def load_boot(auto_start)
    env = { "RACK_ENV" => "test", "SFL_AUTO_START_DOCKER" => auto_start, "SFL_SKIP_LLM_BOOT" => "true" }
    Open3.capture3(env, RbConfig.ruby, "-e", probe, chdir: root)
  end

  it "passes enabled: false to DockerServices.ensure_running! when SFL_AUTO_START_DOCKER is unset" do
    out, err, status = load_boot(nil)

    expect([status.success?, out]).to eq([true, "enabled=false\n"]), err
  end

  it "passes enabled: true to DockerServices.ensure_running! when SFL_AUTO_START_DOCKER=1" do
    out, err, status = load_boot("1")

    expect([status.success?, out]).to eq([true, "enabled=true\n"]), err
  end
end
