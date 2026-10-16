# frozen_string_literal: true

class Sfl
  hash_branch("health") do |r|
    r.is do
      r.get do
        { status: "ok" }
      end
    end
  end
end
