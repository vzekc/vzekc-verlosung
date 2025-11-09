# frozen_string_literal: true

Fabricator(:lottery, from: "VzekcVerlosung::Lottery") do
  topic { Fabricate(:topic) }
  display_id { sequence(:display_id, 401) }
  state "draft"
  duration_days 14
end
