# frozen_string_literal: true

Fabricator(:lottery_packet, from: "VzekcVerlosung::LotteryPacket") do
  transient :lottery_obj

  lottery { |attrs| attrs[:lottery_obj] || Fabricate(:lottery) }
  post do |attrs|
    # Only create post for regular packets (not Abholerpakete)
    unless attrs[:abholerpaket]
      topic = attrs[:lottery].topic
      Fabricate(:post, topic: topic)
    end
  end
  title { sequence(:title) { |i| "Test Packet #{i}" } }
  ordinal { sequence(:ordinal, 1) }
  erhaltungsbericht_required true
  abholerpaket false
end

# Abholerpaket variant - no post created, pre-assigned winner
Fabricator(:lottery_packet_abholerpaket, from: :lottery_packet) do
  title "Abholerpaket"
  ordinal 0
  abholerpaket true
  winner { |attrs| attrs[:lottery].topic.user }
  won_at { Time.zone.now }
  collected_at { Time.zone.now }
  post nil
end
