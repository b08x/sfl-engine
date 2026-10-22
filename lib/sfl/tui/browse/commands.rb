# frozen_string_literal: true

require "dry/monads"

module SFL
  module TUI
    module Browse
      # Commands Browse's update returns. Each is a Proc built by
      # SafeCommand: calling it does the I/O and returns a message.
      module Commands
        extend self

        NO_REVIEWER = "SFL_REVIEWER_NAME is not set; review decisions need a reviewer name"
        # The Messages::Failed source of a failed load, which Browse records.
        LOAD_SOURCE = :collections

        # @return [Proc] -> Messages::BrowseLoaded
        def load(services)
          SafeCommand.wrap(source: LOAD_SOURCE, logger: services.logger) do
            source = services.source
            reviews = Reviews.new(content: source.content_reviews, annotations: source.annotation_reviews)
            Messages::BrowseLoaded.new(tree: Tree.load(source), reviews:)
          end
        end

        # @return [Proc] -> Messages::ClausesLoaded
        def load_clauses(services, section_id)
          wrap(services) { Messages::ClausesLoaded.new(section_id:, clauses: services.source.clauses(section_id)) }
        end

        # @param decision [String] "approve" or "reject"
        # @return [Proc] -> Messages::Reviewed
        def decide(services, item, decision)
          wrap(services) do
            next Dry::Monads::Failure(NO_REVIEWER) unless services.reviewer

            services.review_queue.decide(id: item[:id], decision:, reviewer: services.reviewer)
            services.logger.info("content review decided", review_id: item[:id], decision:, section_id: item[:section_id])
            Messages::Reviewed.new("#{decision}: #{item[:section_id]}")
          end
        end

        # Opens the generated text in the editor, recompiles the section from
        # the edited text as a `recompile` run, then records an edit decision.
        # @return [Proc] -> Messages::Reviewed
        def edit(services, item, collection)
          wrap(services) do
            next Dry::Monads::Failure(NO_REVIEWER) unless services.reviewer

            text = services.editor.edit(item[:generated_text].to_s)
            recompile(services, item, text, collection).fmap do
              services.review_queue.decide(id: item[:id], decision: "edit", reviewer: services.reviewer)
              Messages::Reviewed.new("edited and recompiled: #{item[:section_id]}")
            end
          end
        end

        # Shows the image inline when the terminal host can (kitty), else
        # opens it in the external viewer.
        # @return [Proc] -> Messages::Status
        def open(services, item)
          wrap(services) do
            path = item[:source_file]
            next Messages::Status.new("shown #{path} with kitten icat") if inline?(services, path)

            services.opener.open(path)
            Messages::Status.new("opened #{path}")
          end
        end

        # @param format [Symbol] :jsonl or :markdown
        # @return [Proc] -> Messages::Exported
        def export(services, picks, format)
          wrap(services) do
            result = services.exporter.call(picks, format)
            Messages::Exported.new(path: result[:path], count: result[:count])
          end
        end

        private def recompile(services, item, text, collection)
          run_id = services.run_id.call
          section_id = item[:section_id]
          services.run_log.start(run_id:, kind: "recompile", collection:, total: 1, pid: Process.pid, models: services.run_models)
          result = services.recompiler.call(text, section_id:)
          services.run_log.advance(run_id, done: result.success? ? 1 : 0, failed: result.success? ? 0 : 1, current_item: section_id)
          services.run_log.finish(run_id, status: result.success? ? "finished" : "failed")
          services.logger.info("recompile finished", run_id:, section_id:, ok: result.success?)
          result
        end

        # A host that fails is treated like one that cannot show images.
        private def inline?(services, path)
          services.terminal_host.show_image(path)
        rescue Core::Ports::TerminalHost::Error => e
          services.logger.warn("inline image failed, opening the external viewer", path:, error: e.message)
          false
        end

        private def wrap(services, &) = SafeCommand.wrap(source: :browse, logger: services.logger, &)
      end
    end
  end
end
