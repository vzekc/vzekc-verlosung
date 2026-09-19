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

      it "logs ticket_bought notification with lottery and packet context" do
        post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }

        log =
          VzekcVerlosung::NotificationLog.find_by(
            notification_type: "ticket_bought",
            recipient_user_id: admin.id,
          )
        expect(log).to be_present
        expect(log.lottery_id).to eq(lottery.id)
        expect(log.lottery_packet_id).to eq(lottery_packet.id)
        expect(log.success).to eq(true)
      end

      it "names the packet in the ticket_bought notification" do
        post "/vzekc-verlosung/tickets.json", params: { post_id: lottery_post.id }

        notification =
          Notification.find_by(
            user_id: admin.id,
            notification_type: Notification.types[:vzekc_verlosung_ticket_bought],
          )
        expect(notification.data_hash[:packet_title]).to eq("Test Packet")
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

      it "logs ticket_returned notification with lottery and packet context" do
        delete "/vzekc-verlosung/tickets/#{lottery_post.id}.json"

        log =
          VzekcVerlosung::NotificationLog.find_by(
            notification_type: "ticket_returned",
            recipient_user_id: admin.id,
          )
        expect(log).to be_present
        expect(log.lottery_id).to eq(lottery.id)
        expect(log.lottery_packet_id).to eq(lottery_packet.id)
        expect(log.success).to eq(true)
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

  describe "#set_erhaltungsbericht_required" do
    fab!(:other_user, :user)
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
        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: false,
            }
        expect(response.status).to eq(403)
      end
    end

    context "when user is the lottery owner and lottery is pre-draw" do
      before { sign_in(admin) }

      it "clears the flag" do
        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: false,
            }

        expect(response.status).to eq(200)
        expect(response.parsed_body["erhaltungsbericht_required"]).to eq(false)
        expect(lottery_packet.reload.erhaltungsbericht_required).to eq(false)
      end

      it "sets the flag" do
        lottery_packet.update!(erhaltungsbericht_required: false)

        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: true,
            }

        expect(response.status).to eq(200)
        expect(response.parsed_body["erhaltungsbericht_required"]).to eq(true)
        expect(lottery_packet.reload.erhaltungsbericht_required).to eq(true)
      end

      it "is idempotent" do
        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: true,
            }

        expect(response.status).to eq(200)
        expect(lottery_packet.reload.erhaltungsbericht_required).to eq(true)
      end

      it "works for abholerpaket" do
        lottery_packet.update!(abholerpaket: true)

        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: false,
            }

        expect(response.status).to eq(200)
        expect(lottery_packet.reload.erhaltungsbericht_required).to eq(false)
      end

      it "returns 400 if required parameter is missing" do
        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json"
        expect(response.status).to eq(400)
      end

      it "returns 404 if post does not exist" do
        put "/vzekc-verlosung/packets/999999/erhaltungsbericht-required.json",
            params: {
              required: false,
            }
        expect(response.status).to eq(404)
      end
    end

    context "when user is not the lottery owner" do
      before { sign_in(other_user) }

      it "returns 403" do
        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: false,
            }

        expect(response.status).to eq(403)
        expect(lottery_packet.reload.erhaltungsbericht_required).to eq(true)
      end
    end

    context "when the lottery has already been drawn" do
      before do
        lottery.update!(drawn_at: 1.day.ago, state: "finished")
        sign_in(admin)
      end

      it "returns 422" do
        put "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-required.json",
            params: {
              required: false,
            }

        expect(response.status).to eq(422)
        expect(lottery_packet.reload.erhaltungsbericht_required).to eq(true)
      end
    end
  end

  describe "#erhaltungsbericht_draft" do
    fab!(:other_user, :user)
    fab!(:erhaltungsberichte_category, :category)
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
    let!(:winner_entry) do
      VzekcVerlosung::LotteryPacketWinner.create!(
        lottery_packet: lottery_packet,
        winner_user_id: user.id,
        instance_number: 1,
        won_at: 2.days.ago,
        collected_at: 1.day.ago,
        fulfillment_state: "received",
      )
    end

    before do
      SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id =
        erhaltungsberichte_category.id.to_s
    end

    context "when user is not logged in" do
      it "returns 403" do
        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"
        expect(response.status).to eq(403)
      end
    end

    context "when the winner requests the draft" do
      before { sign_in(user) }

      it "returns the composer payload" do
        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["category_id"]).to eq(erhaltungsberichte_category.id)
        expect(json["title"]).to eq("Test Packet aus #{topic.title}")
        expect(json["packet_post_id"]).to eq(lottery_post.id)
        expect(json["packet_topic_id"]).to eq(topic.id)
        expect(json["instance_number"]).to eq(1)
        expect(json["packet_url"]).to eq("#{topic.relative_url}/#{lottery_post.post_number}")
      end

      it "returns the lottery title alone in single packet mode" do
        lottery.update!(packet_mode: "ein")

        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"

        expect(response.parsed_body["title"]).to eq(topic.title)
      end

      it "returns the existing report when one was already written" do
        report = Fabricate(:topic, user: user, category: erhaltungsberichte_category)
        winner_entry.link_report!(report)

        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"

        expect(response.status).to eq(200)
        expect(response.parsed_body["existing_topic_url"]).to eq(report.relative_url)
      end

      it "returns 422 when the packet is not collected yet" do
        winner_entry.update!(fulfillment_state: "won", collected_at: nil)

        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"

        expect(response.status).to eq(422)
      end

      it "returns 422 when the Erhaltungsberichte category is not configured" do
        SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = ""

        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"

        expect(response.status).to eq(422)
      end

      it "returns 404 when the post does not exist" do
        get "/vzekc-verlosung/packets/999999/erhaltungsbericht-draft.json"
        expect(response.status).to eq(404)
      end
    end

    context "when a non-winner requests the draft" do
      before { sign_in(other_user) }

      it "returns 403" do
        get "/vzekc-verlosung/packets/#{lottery_post.id}/erhaltungsbericht-draft.json"
        expect(response.status).to eq(403)
      end
    end
  end
end
