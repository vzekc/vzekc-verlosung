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
  quantity 1
  erhaltungsbericht_required true
  abholerpaket false
end

# Abholerpaket variant - no post created, winner is assigned via after_create
Fabricator(:lottery_packet_abholerpaket, from: :lottery_packet) do
  title "Abholerpaket"
  ordinal 0
  abholerpaket true
  post nil

  after_create do |packet, _attrs|
    # Assign the lottery creator as winner of the Abholerpaket
    VzekcVerlosung::LotteryPacketWinner.create!(
      lottery_packet: packet,
      winner_user_id: packet.lottery.topic.user_id,
      instance_number: 1,
      won_at: Time.zone.now,
      collected_at: Time.zone.now,
    )
  end
end
