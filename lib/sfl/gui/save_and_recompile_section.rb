# frozen_string_literal: true

require "dry/monads"

require_relative "failure_message"

module SFL
  module GUI
    # The editable-text entry plus its "Save & Recompile" button, shared
    # verbatim by ImageReviewControl and TextReviewControl (SIFT S-4 — the two
    # were byte-identical duplicates). Not promoted to its own custom control:
    # two call sites in the same pane don't earn one, and a plain module keeps
    # the emitted controls as direct children of each control's own
    # vertical_box, where their layout already works.
    #
    # Including controls must expose #viewmodel (the `options :viewmodel`
    # reader every control in this app already declares).
    module SaveAndRecompileSection
      # Held so the click handler can toggle them while a recompile is in
      # flight. Assigned through an explicit `control = self` capture because
      # `self` inside a Glimmer DSL block is the control proxy, not this object
      # — the same idiom ImageReviewControl uses for its image_area.
      attr_accessor :save_button, :recompile_status_label

      # Emits the entry, a status label and the button into whichever Glimmer
      # container is currently open at the call site.
      def save_and_recompile_section
        control = self

        multiline_entry {
          text <=> [viewmodel, :edited_text]
        }

        control.recompile_status_label = label {
          text ""
        }

        control.save_button = button("Save & Recompile") {
          on_clicked { control.start_save_and_recompile }
        }
      end

      # SIFT F-1: ReviewQueueViewModel#save_and_recompile! runs the whole
      # pipeline — LLM calls and embedding over the network, seconds to minutes.
      # Called inline from on_clicked it blocks the libui event loop, so the
      # window stops repainting and the desktop marks it "not responding".
      #
      # The fix lives entirely here in the view: the viewmodel method keeps its
      # plain synchronous Result contract (and its unit tests) untouched, and
      # this control simply stops calling it on the UI thread. The button is
      # disabled for the duration so a second click can't start a concurrent
      # recompile of the same row, and the result is marshalled back through
      # queue_main because no control may be touched off the main thread.
      def start_save_and_recompile
        apply_busy_state(true)

        # rubocop:disable ThreadSafety/NewThread -- offloading blocking work off
        # the libui event loop is the entire point; queue_main below is the
        # documented way back onto the UI thread, and the disabled button means
        # only one of these can be in flight per control at a time.
        Thread.new do
          result = perform_save_and_recompile

          Glimmer::LibUI.queue_main do
            apply_busy_state(false)
            msg_box_error("Recompile failed", FailureMessage.call(result.failure)) if result.failure?
          end
        end
        # rubocop:enable ThreadSafety/NewThread
      end

      # #save_and_recompile! already converts its own exceptions to Failure, but
      # anything it misses would die silently inside the Thread and strand the
      # button disabled forever. This guarantees a Result reaches queue_main.
      #
      # @return [Dry::Monads::Result]
      private def perform_save_and_recompile
        viewmodel.save_and_recompile!
      rescue => e
        Dry::Monads::Failure(e.message)
      end

      # @param busy [Boolean]
      private def apply_busy_state(busy)
        save_button&.enabled = !busy
        recompile_status_label&.text = busy ? "Recompiling…" : ""
      end
    end
  end
end
