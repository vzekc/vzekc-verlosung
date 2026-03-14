# frozen_string_literal: true

Fabricator(:merch_packet, from: "VzekcVerlosung::MerchPacket") do
  donation { Fabricate(:donation) }
  donor_name "Max Mustermann"
  donor_street "Musterstraße"
  donor_street_number "42"
  donor_postcode "12345"
  donor_city "Musterstadt"
  state "pending"
end

Fabricator(:standalone_merch_packet, from: "VzekcVerlosung::MerchPacket") do
  title "Dankespaket für Max"
  donor_name "Max Mustermann"
  donor_street "Musterstraße"
  donor_street_number "42"
  donor_postcode "12345"
  donor_city "Musterstadt"
  state "pending"
end
