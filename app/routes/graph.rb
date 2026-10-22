# frozen_string_literal: true

class Sfl
  hash_branch("graph") do |r|
    r.is "nodes" do
      r.get do
        section_id = presence(reject_legacy_id(r.params)["section_id"])
        ctx.graph_repository.nodes(section_id:).map { |n| SFL::Core::Wire.dump(n) }
      end
    end

    r.is "edges" do
      r.get do
        section_id = presence(reject_legacy_id(r.params)["section_id"])
        repo = ctx.graph_repository

        structural = repo.parent_child_edges(section_id:)
        semantic = repo.nodes(section_id:).flat_map { |n| repo.semantic_neighbors(n.id) }

        (structural + semantic).map { |e| SFL::Core::Wire.dump(e) }
      end
    end
  end
end
