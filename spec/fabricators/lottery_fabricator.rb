# frozen_string_literal: true

Fabricator(:lottery, from: "VzekcVerlosung::Lottery") do
  topic { Fabricate(:topic) }
  state "active"
  duration_days 14
  drawing_mode "automatic"
end
