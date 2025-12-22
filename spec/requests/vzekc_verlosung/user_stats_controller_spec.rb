# frozen_string_literal: true

require "rails_helper"

RSpec.describe VzekcVerlosung::UserStatsController do
  fab!(:user)
  fab!(:another_user, :user)
  fab!(:lottery_category, :category)

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_category_id = lottery_category.id.to_s
  end

  describe "GET /vzekc-verlosung/users/:username" do
    context "when not logged in" do
      it "returns user stats" do
        get "/vzekc-verlosung/users/#{user.username}.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json).to have_key("stats")
        expect(json).to have_key("luck")
        expect(json).to have_key("won_packets")
        expect(json).to have_key("lotteries_created")
        expect(json).to have_key("pickups")
      end
    end

    context "when user does not exist" do
      it "returns 404" do
        get "/vzekc-verlosung/users/nonexistent_user.json"
        expect(response.status).to eq(404)
      end
    end

    context "with lottery data" do
      fab!(:lottery_topic) { Fabricate(:topic, category: lottery_category, user: user) }
      fab!(:lottery) do
        VzekcVerlosung::Lottery.create!(
          topic: lottery_topic,
          state: "finished",
          drawing_mode: "automatic",
          ends_at: 1.day.ago,
          drawn_at: 1.day.ago,
        )
      end
      fab!(:packet_post) { Fabricate(:post, topic: lottery_topic, post_number: 2) }
      fab!(:lottery_packet) do
        VzekcVerlosung::LotteryPacket.create!(
          lottery: lottery,
          post: packet_post,
          title: "Test Packet",
          ordinal: 1,
        )
      end

      before do
        VzekcVerlosung::LotteryTicket.create!(user: another_user, post: packet_post)
        lottery_packet.mark_winner!(another_user, 1.day.ago)
      end

      it "returns correct stats for lottery creator" do
        get "/vzekc-verlosung/users/#{user.username}.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["stats"]["lotteries_created"]).to eq(1)
        expect(json["lotteries_created"].length).to eq(1)
        expect(json["lotteries_created"][0]["title"]).to eq(lottery_topic.title)
      end

      it "returns correct stats for winner" do
        get "/vzekc-verlosung/users/#{another_user.username}.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["stats"]["packets_won"]).to eq(1)
        expect(json["stats"]["tickets_count"]).to eq(1)
        expect(json["won_packets"].length).to eq(1)
        expect(json["won_packets"][0]["title"]).to eq("Test Packet")
      end

      it "calculates luck factor correctly" do
        get "/vzekc-verlosung/users/#{another_user.username}.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["luck"]["wins"]).to eq(1)
        expect(json["luck"]["participated"]).to eq(1)
        expect(json["luck"]["expected"]).to eq(1.0)
        expect(json["luck"]["luck"]).to eq(0.0)
      end
    end
  end
end
