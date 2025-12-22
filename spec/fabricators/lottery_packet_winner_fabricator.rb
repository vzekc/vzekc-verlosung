# frozen_string_literal: true

Fabricator(:lottery_packet_winner, from: "VzekcVerlosung::LotteryPacketWinner") do
  transient :packet

  lottery_packet { |attrs| attrs[:packet] || Fabricate(:lottery_packet) }
  winner { Fabricate(:user) }
  instance_number 1
  won_at { Time.zone.now }
end
