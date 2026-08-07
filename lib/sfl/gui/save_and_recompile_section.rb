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

      # SIFT F-1: recompiling runs the whole pipeline — LLM calls and embedding
      # over the network, seconds to minutes. Called inline from on_clicked it
      # blocks the libui event loop, so the window stops repainting and the
      # desktop marks it "not responding".
      #
      # The work is split rather than simply backgrounded, because only half of
      # it is safe to move. Glimmer's observers notify **synchronously in the
      # calling thread** (glimmer-2.8.2 observable_model.rb#notify_observers is
      # a plain `each { observer.call(...) }`, and there is no queue_main
      # anywhere in the gem). So assigning an observed attribute like `items`
      # pushes straight into a libui C call on whatever thread did the assigning
      # — undefined GTK behaviour off the main thread, on every successful run,
      # not just under an unlucky interleaving.
      #
      # Hence:
      #   Thread     -> #compile_for_recompile, which mutates nothing and only
      #                 reaches the network. No observed writer fires.
      #   queue_main -> #finish_recompile!, which is where decide!/refresh!
      #                 assign items/selected_item/edited_text, plus the button
      #                 and dialog updates. queue_main callbacks run
      #                 sequentially on the main thread, so the state mutation
      #                 and the UI update stay ordered and on-thread together.
      #
      # The button stays disabled across both phases so a second click cannot
      # start a concurrent recompile of the same row.
      def start_save_and_recompile
        apply_busy_state(true) # already on the UI thread: on_clicked runs there

        # Captured here, on the UI thread, before the compile starts — names the
        # row that was selected at click time. The table stays interactive
        # during the compile, so selected_item can move to a different row
        # before the thread finishes; #finish_recompile! compares against this
        # captured id and refuses to record the decision against whatever
        # happens to be selected when the compile completes (SIFT follow-up:
        # row-identity check).
        compiled_item_id = viewmodel.selected_item_id

        # rubocop:disable ThreadSafety/NewThread -- offloading the network-bound
        # compile off the libui event loop is the entire point. Nothing in this
        # block touches an observed attribute; see the comment above.
        Thread.new do
          compile_result = perform_compile

          Glimmer::LibUI.queue_main do
            result = finish_recompile(compile_result, compiled_item_id)
            apply_busy_state(false)
            msg_box_error("Recompile failed", FailureMessage.call(result.failure)) if result.failure?
          end
        end
        # rubocop:enable ThreadSafety/NewThread
      end

      # #compile_for_recompile already converts pipeline exceptions to Failure,
      # but anything it misses would die silently inside the Thread and strand
      # the button disabled forever. This guarantees a Result reaches queue_main.
      #
      # @return [Dry::Monads::Result]
      private def perform_compile
        viewmodel.compile_for_recompile
      rescue => e
        Dry::Monads::Failure(e.message)
      end

      # Same belt-and-braces on the main-thread half: if this raised, the
      # queue_main block would abort before re-enabling the button.
      #
      # @return [Dry::Monads::Result]
      private def finish_recompile(compile_result, compiled_item_id)
        viewmodel.finish_recompile!(compile_result, compiled_item_id:)
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
