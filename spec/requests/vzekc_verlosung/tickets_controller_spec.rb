# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::TicketsController do
  fab!(:user)
  fab!(:admin)
  fab!(:topic) { Fabricate(:topic, user: admin) }
  let!(:lottery) do
    VzekcVerlosung::Lottery.create!(topic_id: topic.id, state: "active", duration_days: 14)
  end

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#create" do
    let!(:lottery_post) { Fabricate(:post, topic: topic, user: admin) }
    let!(:lottery_packet) do
      VzekcVerlosung::LotteryPacket.create!(
        lottery_id: lottery.id,
        post_id: lottery_post.id,
        ordinal: 1,
        title: "Test Packet",
        erhaltungsbericht_required: true,
        abholerpaket: false,
      )
    end

    context "when user is not logged in" do
      it "returns 403" do
        post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }
        expect(response.status).to eq(403)
      end
    end

    context "when user is logged in" do
      before { sign_in(user) }

      it "creates a ticket successfully" do
        expect {
          post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }
        }.to change { VzekcVerlosung::LotteryTicket.count }.by(1)

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["success"]).to eq("OK")
        expect(json["has_ticket"]).to eq(true)
        expect(json["ticket_count"]).to eq(1)
      end

      it "returns error if post not found" do
        post "/vzekc-verlosung/tickets.json", params: { post_id: 999_999 }
        expect(response.status).to eq(404)
      end

      context "when lottery is finished" do
        before { lottery.update!(state: "finished") }

        it "prevents ticket drawing" do
          expect {
            post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }
          }.not_to change { VzekcVerlosung::LotteryTicket.count }

          expect(response.status).to eq(422)
          json = response.parsed_body
          expect(json["errors"]).to include("Lottery is not active")
        end
      end

      context "when lottery has ended" do
        before { lottery.update!(ends_at: 1.day.ago) }

        it "prevents ticket drawing" do
          expect {
            post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }
          }.not_to change { VzekcVerlosung::LotteryTicket.count }

          expect(response.status).to eq(422)
          json = response.parsed_body
          expect(json["errors"]).to include("Lottery has ended")
        end
      end

      context "when trying to draw ticket for Abholerpaket" do
        let!(:abholerpaket_post) { Fabricate(:post, topic: topic, user: admin) }
        let!(:abholerpaket) do
          VzekcVerlosung::LotteryPacket.create!(
            lottery_id: lottery.id,
            post_id: abholerpaket_post.id,
            ordinal: 0,
            title: "Abholerpaket",
            erhaltungsbericht_required: false,
            abholerpaket: true,
          )
        end

        it "prevents ticket drawing for Abholerpaket" do
          expect {
            post "/vzekc-verlosung/tickets.json", params: { post_id: abholerpaket_post.id }
          }.not_to change { VzekcVerlosung::LotteryTicket.count }

          expect(response.status).to eq(422)
          json = response.parsed_body
          expect(json["errors"]).to include("Cannot draw tickets for the Abholerpaket")
        end
      end

      context "when user already has a ticket" do
        before { VzekcVerlosung::LotteryTicket.create!(post_id: lottery_post.id, user_id: user.id) }

        it "returns validation error" do
          expect {
            post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }
          }.not_to change { VzekcVerlosung::LotteryTicket.count }

          expect(response.status).to eq(422)
        end
      end
    end
  end

  describe "#destroy" do
    let!(:lottery_post) { Fabricate(:post, topic: topic, user: admin) }
    let!(:lottery_packet) do
      VzekcVerlosung::LotteryPacket.create!(
        lottery_id: lottery.id,
        post_id: lottery_post.id,
        ordinal: 1,
        title: "Test Packet",
        erhaltungsbericht_required: true,
        abholerpaket: false,
      )
    end
    let!(:ticket) do
      VzekcVerlosung::LotteryTicket.create!(post_id: lottery_post.id, user_id: user.id)
    end

    context "when user is not logged in" do
      it "returns 403" do
        delete "/vzekc-verlosung/tickets/#{lottery_post.id}.json"
        expect(response.status).to eq(403)
      end
    end

    context "when user is logged in" do
      before { sign_in(user) }

      it "destroys the ticket successfully" do
        expect { delete "/vzekc-verlosung/tickets/#{lottery_post.id}.json" }.to change {
          VzekcVerlosung::LotteryTicket.count
        }.by(-1)

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["success"]).to eq("OK")
        expect(json["has_ticket"]).to eq(false)
      end

      it "returns error if ticket not found" do
        delete "/vzekc-verlosung/tickets/999999.json"
        expect(response.status).to eq(404)
      end

      context "when lottery is finished" do
        before { lottery.update!(state: "finished") }

        it "prevents ticket return" do
          expect { delete "/vzekc-verlosung/tickets/#{lottery_post.id}.json" }.not_to change {
            VzekcVerlosung::LotteryTicket.count
          }

          expect(response.status).to eq(422)
          json = response.parsed_body
          expect(json["errors"]).to include("Lottery is not active")
        end
      end

      context "when lottery has ended" do
        before { lottery.update!(ends_at: 1.day.ago) }

        it "prevents ticket return" do
          expect { delete "/vzekc-verlosung/tickets/#{lottery_post.id}.json" }.not_to change {
            VzekcVerlosung::LotteryTicket.count
          }

          expect(response.status).to eq(422)
          json = response.parsed_body
          expect(json["errors"]).to include("Lottery has ended")
        end
      end
    end
  end

  describe "#packet_status" do
    let!(:lottery_post) { Fabricate(:post, topic: topic, user: admin) }
    let!(:lottery_packet) do
      VzekcVerlosung::LotteryPacket.create!(
        lottery_id: lottery.id,
        post_id: lottery_post.id,
        ordinal: 1,
        title: "Test Packet",
        erhaltungsbericht_required: true,
        abholerpaket: false,
      )
    end

    context "when user is not logged in" do
      it "returns 403" do
        get "/vzekc-verlosung/tickets/packet-status/#{lottery_post.id}.json"
        expect(response.status).to eq(403)
      end
    end

    context "when user is logged in" do
      before { sign_in(user) }

      it "returns ticket status when user has no ticket" do
        get "/vzekc-verlosung/tickets/packet-status/#{lottery_post.id}.json"

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["has_ticket"]).to eq(false)
        expect(json["ticket_count"]).to eq(0)
        expect(json["users"]).to eq([])
      end

      it "returns ticket status when user has a ticket" do
        VzekcVerlosung::LotteryTicket.create!(post_id: lottery_post.id, user_id: user.id)

        get "/vzekc-verlosung/tickets/packet-status/#{lottery_post.id}.json"

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["has_ticket"]).to eq(true)
        expect(json["ticket_count"]).to eq(1)
        expect(json["users"].length).to eq(1)
        expect(json["users"][0]["username"]).to eq(user.username)
      end
    end
  end
end
