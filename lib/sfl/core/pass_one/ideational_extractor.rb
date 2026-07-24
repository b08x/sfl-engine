# frozen_string_literal: true

module SFL
  module Core
    module PassOne
      # Ideational Extractor (Pass 1 post-processing): maps syntactic
      # dependency structures to SFL Ideational metafunction categories —
      # process type, participants (semantic roles), and circumstances
      # (adjuncts). Rule-based, operating on SpacySidecarParser's output;
      # no LLM calls.
      # rubocop:disable Metrics/ClassLength -- mostly the five verb-lemma constant lists
      # (one word per line per this project's array style), not method complexity.
      class IdeationalExtractor
        # spaCy dependency labels mapped to SFL participant roles.
        PARTICIPANT_ROLES = {
          "nsubj" => "Actor",          # Subject of material process
          "nsubjpass" => "Goal",       # Passive subject
          "dobj" => "Goal",            # Direct object
          "iobj" => "Recipient",       # Indirect object
          "attr" => "Attribute",       # Attributive complement
          "oprd" => "Attribute",       # Object predicate
          "pobj" => "Circumstance",    # Object of preposition
          "prep" => "Circumstance",    # Prepositional modifier
          "advmod" => "Circumstance",  # Adverbial modifier
          "advcl" => "Circumstance",   # Adverbial clause modifier
          "acomp" => "Attribute",      # Adjectival complement
          "xcomp" => "Process",        # Open clausal complement
          "ccomp" => "Process",        # Clausal complement
          "conj" => "Participant",     # Conjunct
          "appos" => "Participant",    # Appositional modifier
        }.freeze

        # Verb POS tags that indicate process types, keyed by the tag's
        # first two characters (e.g. "VBZ" -> "VB").
        PROCESS_INDICATORS = {
          "VB" => "material",
          # Modal auxiliaries (MD) don't define process type on their own —
          # the lexical verb complement does. Default to "mental" since modal
          # clauses are typically epistemic/deontic (mental/relational domain).
          "MD" => "mental",
        }.freeze

        MENTAL_VERBS = %w[
          think
          know
          believe
          understand
          feel
          see
          hear
          want
          need
          like
          love
          hate
          consider
          suppose
          expect
          remember
          forget
          imagine
          notice
          realize
        ].freeze

        RELATIONAL_VERBS = %w[be seem become appear remain stay look sound taste smell feel].freeze

        VERBAL_VERBS = %w[
          say
          tell
          speak
          talk
          ask
          answer
          reply
          respond
          declare
          announce
          report
          explain
          suggest
          propose
        ].freeze

        BEHAVIORAL_VERBS = %w[breathe smile sneeze cry laugh look watch listen cough sleep].freeze

        EXISTENTIAL_VERBS = %w[be exist].freeze

        # @param clause [SFL::Core::Types::SyntacticClause] output from SpacySidecarParser
        # @return [SFL::Core::Types::IdeationalPayload]
        def extract(clause)
          root_token = clause.tokens[clause.root_index]
          return empty_payload(clause.id) if root_token.nil?

          Types::IdeationalPayload.new(
            clause_id: clause.id,
            process_type: classify_process(root_token, clause),
            participants: extract_participants(clause),
            circumstances: extract_circumstances(clause),
            raw_transitivity: build_transitivity_hash(root_token, clause)
          )
        end

        private def classify_process(root_token, clause)
          return "mental" if mental_verb?(root_token)
          return "relational" if relational_verb?(root_token)
          return "verbal" if verbal_verb?(root_token)
          return "behavioral" if behavioral_verb?(root_token)
          return "existential" if existential?(root_token, clause)

          PROCESS_INDICATORS.fetch(root_token.tag[0..1], "material")
        end

        private def mental_verb?(token) = MENTAL_VERBS.include?(token.lemma.downcase)
        private def relational_verb?(token) = RELATIONAL_VERBS.include?(token.lemma.downcase)
        private def verbal_verb?(token) = VERBAL_VERBS.include?(token.lemma.downcase)
        private def behavioral_verb?(token) = BEHAVIORAL_VERBS.include?(token.lemma.downcase)

        private def existential?(token, clause)
          clause.text.strip.downcase.start_with?("there ") && EXISTENTIAL_VERBS.include?(token.lemma.downcase)
        end

        private def extract_participants(clause)
          clause.tokens.filter_map do |token|
            role = PARTICIPANT_ROLES[token.dep]
            Types::Participant.new(role:, text: token.text) if role && role != "Circumstance"
          end
        end

        private def extract_circumstances(clause)
          clause.tokens.filter_map do |token|
            role = PARTICIPANT_ROLES[token.dep]
            "#{token.dep}:#{token.text}" if role == "Circumstance"
          end
        end

        private def build_transitivity_hash(root_token, clause)
          {
            root: { text: root_token.text, lemma: root_token.lemma, pos: root_token.pos, tag: root_token.tag },
            dependencies: clause.tokens.map { |t| { text: t.text, dep: t.dep, pos: t.pos, tag: t.tag } },
          }
        end

        private def empty_payload(clause_id)
          Types::IdeationalPayload.new(
            clause_id:, process_type: "material", participants: [], circumstances: [], raw_transitivity: {}
          )
        end
      end
      # rubocop:enable Metrics/ClassLength
    end
  end
end
