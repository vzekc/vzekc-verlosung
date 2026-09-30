# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::LotteryHistoryController do
  fab!(:user)
  fab!(:winner, :user)
  fab!(:old_lottery) { Fabricate(:lottery, state: "finished", drawn_at: 8.months.ago) }
  fab!(:recent_lottery) { Fabricate(:lottery, state: "finished", drawn_at: 2.months.ago) }
  fab!(:old_packet) { Fabricate(:lottery_packet, lottery: old_lottery) }
  fab!(:recent_packet) { Fabricate(:lottery_packet, lottery: recent_lottery) }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    sign_in(user)
  end

  describe "GET /vzekc-verlosung/history/stats" do
    it "counts all finished lotteries without a period" do
      get "/vzekc-verlosung/history/stats.json"

      expect(response.parsed_body["total_lotteries"]).to eq(2)
    end

    it "counts only lotteries drawn within the period" do
      get "/vzekc-verlosung/history/stats.json", params: { period: "6m" }

      expect(response.parsed_body["total_lotteries"]).to eq(1)
    end
  end

  describe "GET /vzekc-verlosung/history/leaderboard" do
    before do
      Fabricate(:lottery_packet_winner, packet: old_packet, winner: winner, won_at: 8.months.ago)
      Fabricate(:lottery_packet_winner, packet: recent_packet, winner: winner, won_at: 2.months.ago)
    end

    it "counts wins within the period" do
      get "/vzekc-verlosung/history/leaderboard.json", params: { period: "3m" }

      expect(response.parsed_body["wins"].map { |e| [e["user"]["id"], e["count"]] }).to eq(
        [[winner.id, 1]],
      )
    end

    it "lists users with wins waiting longer than six weeks" do
      get "/vzekc-verlosung/history/leaderboard.json"

      expect(response.parsed_body["uncollected"].map { |e| [e["user"]["id"], e["count"]] }).to eq(
        [[winner.id, 2]],
      )
    end

    context "with collected, shipped, fresh, silenced, and Abholerpaket wins" do
      fab!(:fresh_lottery) { Fabricate(:lottery, state: "finished", drawn_at: 2.weeks.ago) }

      before do
        VzekcVerlosung::LotteryPacketWinner.update_all(fulfillment_state: "completed")
        Fabricate(
          :lottery_packet_winner,
          packet: Fabricate(:lottery_packet, lottery: recent_lottery),
          winner: winner,
          fulfillment_state: "shipped",
          won_at: 2.months.ago,
        )
        Fabricate(
          :lottery_packet_winner,
          packet: Fabricate(:lottery_packet, lottery: fresh_lottery),
          winner: winner,
          won_at: 2.weeks.ago,
        )
        Fabricate(
          :lottery_packet_winner,
          packet: Fabricate(:lottery_packet, lottery: recent_lottery, notifications_silenced: true),
          winner: winner,
          won_at: 2.months.ago,
        )
        Fabricate(
          :lottery_packet_winner,
          packet:
            Fabricate(
              :lottery_packet,
              lottery: recent_lottery,
              abholerpaket: true,
              post: Fabricate(:post, topic: recent_lottery.topic),
            ),
          winner: winner,
          won_at: 2.months.ago,
        )
      end

      it "leaves them out" do
        get "/vzekc-verlosung/history/leaderboard.json"

        expect(response.parsed_body["uncollected"]).to be_empty
      end
    end
  end

  describe "GET /vzekc-verlosung/history/leaderboard/:kind/:username" do
    fab!(:other_user, :user)

    before do
      Fabricate(:lottery_ticket, user: winner, post: old_packet.post)
      Fabricate(:lottery_ticket, user: other_user, post: old_packet.post)
      Fabricate(:lottery_ticket, user: winner, post: recent_packet.post)
      Fabricate(:lottery_packet_winner, packet: old_packet, winner: winner, won_at: 8.months.ago)
    end

    it "lists the lotteries the user ran" do
      get "/vzekc-verlosung/history/leaderboard/lotteries/#{recent_lottery.topic.user.username}.json"

      expect(response.parsed_body["entries"].map { |e| e["title"] }).to eq(
        [recent_lottery.topic.title],
      )
    end

    it "lists the packets the user drew tickets for, with participants and outcome" do
      get "/vzekc-verlosung/history/leaderboard/tickets/#{winner.username}.json"

      expect(
        response.parsed_body["entries"].map { |e| [e["title"], e["participants"], e["won"]] },
      ).to eq([[recent_packet.title, 1, false], [old_packet.title, 2, true]])
    end

    it "lists the user's wins within the period" do
      get "/vzekc-verlosung/history/leaderboard/wins/#{winner.username}.json",
          params: {
            period: "1y",
          }

      expect(response.parsed_body["entries"].map { |e| [e["title"], e["state"]] }).to eq(
        [[old_packet.title, "won"]],
      )
    end

    it "lists uncollected wins with the lottery owner holding them" do
      get "/vzekc-verlosung/history/leaderboard/uncollected/#{winner.username}.json"

      entry = response.parsed_body["entries"].sole
      expect(entry["owner"]).to eq(old_lottery.topic.user.username)
      expect(entry["days_waiting"]).to be > 200
    end

    it "returns 404 for an unknown user" do
      get "/vzekc-verlosung/history/leaderboard/wins/nobody_here.json"

      expect(response.status).to eq(404)
    end
  end
end
