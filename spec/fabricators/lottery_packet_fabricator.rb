# frozen_string_literal: true

Fabricator(:lottery_packet, from: "VzekcVerlosung::LotteryPacket") do
  transient :lottery_obj

  lottery { lottery_obj || Fabricate(:lottery) }
  post do |attrs|
    topic = attrs[:lottery].topic
    Fabricate(:post, topic: topic)
  end
  title { sequence(:title) { |i| "Test Packet #{i}" } }
end
