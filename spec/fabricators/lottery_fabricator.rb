# frozen_string_literal: true

Fabricator(:lottery, from: "VzekcVerlosung::Lottery") do
  topic { Fabricate(:topic) }
  # Use modulo wrapping to keep display_id in realistic range (401-99400)
  # Prevents integer overflow in tests while maintaining deterministic sequences
  display_id { sequence(:display_id) { |i| (i % 99000) + 401 } }
  state "draft"
  duration_days 14
end
