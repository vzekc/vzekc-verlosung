# frozen_string_literal: true

Fabricator(:lottery, from: "VzekcVerlosung::Lottery") do
  topic { Fabricate(:topic) }
  state "draft"
  duration_days 14
end
