# frozen_string_literal: true

Fabricator(:pickup_offer, from: "VzekcVerlosung::PickupOffer") do
  donation
  user
  state "pending"
end
