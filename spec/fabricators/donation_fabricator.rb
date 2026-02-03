# frozen_string_literal: true

Fabricator(:donation, from: "VzekcVerlosung::Donation") do
  postcode "12345"
  creator_user_id { Fabricate(:user).id }
  state "draft"
end
