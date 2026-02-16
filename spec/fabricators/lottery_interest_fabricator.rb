# frozen_string_literal: true

Fabricator(:lottery_interest, from: "VzekcVerlosung::LotteryInterest") do
  donation
  user
end
