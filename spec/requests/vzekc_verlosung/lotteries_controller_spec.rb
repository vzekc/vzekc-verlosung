# frozen_string_literal: true

RSpec.describe VzekcVerlosung::LotteriesController do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:category)

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#create" do
    before { sign_in(user) }

    let(:valid_params) do
      {
        title: "Hardware Verlosung Januar 2025",
        category_id: category.id,
        duration_days: 14,
        has_abholerpaket: false,
        packets: [{ title: "Packet 1" }, { title: "Packet 2" }],
      }
    end

    context "when request is valid" do
      it "returns success" do
        post "/vzekc-verlosung/lotteries.json", params: valid_params

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["success"]).to eq("OK")
        expect(json["main_topic"]).to be_present
      end

      it "creates topics" do
        expect { post "/vzekc-verlosung/lotteries.json", params: valid_params }.to change {
          Topic.count
        }.by(1).and change { Post.count }.by(3) # 1 main post + 2 packet posts
      end

      it "returns main topic details" do
        post "/vzekc-verlosung/lotteries.json", params: valid_params

        json = response.parsed_body
        expect(json["main_topic"]["title"]).to eq("Hardware Verlosung Januar 2025")
        expect(json["main_topic"]["id"]).to be_present
        expect(json["main_topic"]["url"]).to be_present
      end

      context "with Abholerpaket" do
        it "creates Abholerpaket by default when not specified" do
          params_without_flag = valid_params.except(:has_abholerpaket)
          post "/vzekc-verlosung/lotteries.json", params: params_without_flag

          expect(response.status).to eq(200)
          json = response.parsed_body
          topic = Topic.find(json["main_topic"]["id"])
          lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)

          # Should have 3 packets: 1 Abholerpaket + 2 user packets
          packets = VzekcVerlosung::LotteryPacket.where(lottery_id: lottery.id).order(:ordinal)
          expect(packets.count).to eq(3)

          # First packet should be Abholerpaket with ordinal 0
          abholerpaket = packets.first
          expect(abholerpaket.abholerpaket).to eq(true)
          expect(abholerpaket.title).to eq("Abholerpaket")
          expect(abholerpaket.ordinal).to eq(0)
          expect(abholerpaket.winner_user_id).to eq(user.id)
          expect(abholerpaket.won_at).to be_present

          # User packets should start at ordinal 1
          expect(packets[1].ordinal).to eq(1)
          expect(packets[1].abholerpaket).to eq(false)
          expect(packets[2].ordinal).to eq(2)
          expect(packets[2].abholerpaket).to eq(false)
        end

        it "creates Abholerpaket when explicitly set to true" do
          params_with_abholerpaket = valid_params.merge(has_abholerpaket: true)
          post "/vzekc-verlosung/lotteries.json", params: params_with_abholerpaket

          expect(response.status).to eq(200)
          json = response.parsed_body
          topic = Topic.find(json["main_topic"]["id"])
          lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)

          packets = VzekcVerlosung::LotteryPacket.where(lottery_id: lottery.id).order(:ordinal)
          expect(packets.count).to eq(3)
          expect(packets.first.abholerpaket).to eq(true)
        end

        it "does not create Abholerpaket when set to false" do
          params_without_abholerpaket = valid_params.merge(has_abholerpaket: false)
          post "/vzekc-verlosung/lotteries.json", params: params_without_abholerpaket

          expect(response.status).to eq(200)
          json = response.parsed_body
          topic = Topic.find(json["main_topic"]["id"])
          lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)

          # Should have only 2 user packets
          packets = VzekcVerlosung::LotteryPacket.where(lottery_id: lottery.id).order(:ordinal)
          expect(packets.count).to eq(2)

          # No Abholerpaket should exist
          expect(packets.where(abholerpaket: true).count).to eq(0)

          # User packets should start at ordinal 1
          expect(packets.first.ordinal).to eq(1)
          expect(packets.last.ordinal).to eq(2)
        end

        it "assigns Abholerpaket to creator with erhaltungsbericht required" do
          params_without_flag = valid_params.except(:has_abholerpaket)
          post "/vzekc-verlosung/lotteries.json", params: params_without_flag

          expect(response.status).to eq(200)
          json = response.parsed_body
          topic = Topic.find(json["main_topic"]["id"])
          lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)

          abholerpaket =
            VzekcVerlosung::LotteryPacket.find_by(lottery_id: lottery.id, abholerpaket: true)
          expect(abholerpaket).to be_present
          expect(abholerpaket.winner_user_id).to eq(user.id)
          expect(abholerpaket.won_at).to be_present
          expect(abholerpaket.erhaltungsbericht_required).to eq(true)
        end

        it "uses custom title for Abholerpaket when provided" do
          custom_title = "Dieses System behalte ich"
          params_with_custom_title =
            valid_params.except(:has_abholerpaket).merge(abholerpaket_title: custom_title)
          post "/vzekc-verlosung/lotteries.json", params: params_with_custom_title

          expect(response.status).to eq(200)
          json = response.parsed_body
          topic = Topic.find(json["main_topic"]["id"])
          lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic.id)

          abholerpaket =
            VzekcVerlosung::LotteryPacket.find_by(lottery_id: lottery.id, abholerpaket: true)
          expect(abholerpaket).to be_present
          expect(abholerpaket.title).to eq(custom_title)
          expect(abholerpaket.ordinal).to eq(0)
        end
      end
    end

    context "when request is invalid" do
      it "returns error for missing title" do
        invalid_params = valid_params.merge(title: "")
        post "/vzekc-verlosung/lotteries.json", params: invalid_params

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["failed"]).to eq("FAILED")
        expect(json["errors"]).to be_present
      end

      it "returns error for empty packets" do
        invalid_params = valid_params.merge(packets: [])
        post "/vzekc-verlosung/lotteries.json", params: invalid_params

        expect(response.status).to eq(422)
      end
    end
  end

  describe "#create" do
    context "when user is not logged in" do
      it "returns forbidden" do
        post "/vzekc-verlosung/lotteries.json",
             params: {
               title: "Hardware Verlosung Januar 2025",
               category_id: category.id,
               duration_days: 14,
               has_abholerpaket: false,
               packets: [{ title: "Packet 1" }, { title: "Packet 2" }],
             }

        expect(response.status).to eq(403)
      end
    end
  end

  describe "#publish" do
    before { sign_in(user) }

    fab!(:other_user, :user)
    fab!(:admin)
    let!(:lottery_result) do
      VzekcVerlosung::CreateLottery.call(
        params: {
          title: "Test Lottery",
          category_id: category.id,
          duration_days: 14,
          has_abholerpaket: false,
          packets: [{ title: "Packet 1" }],
        },
        user: user,
        guardian: Guardian.new(user),
      )
    end
    let(:topic) { lottery_result.main_topic }
    let(:lottery) { lottery_result.lottery }

    context "when user is the topic owner" do
      it "publishes the lottery" do
        expect(lottery.state).to eq("draft")

        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(204)
        lottery.reload
        expect(lottery.state).to eq("active")
        expect(lottery.ends_at).to be_present
      end
    end

    context "when user is staff" do
      before { sign_in(admin) }

      it "allows staff to publish" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(204)
        lottery.reload
        expect(lottery.state).to eq("active")
        expect(lottery.ends_at).to be_present
      end
    end

    context "when user is not the owner" do
      before { sign_in(other_user) }

      it "returns forbidden" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(403)
        lottery.reload
        expect(lottery.state).to eq("draft")
      end
    end

    context "when topic is already published" do
      before { lottery.update!(state: "active", ends_at: 14.days.from_now) }

      it "returns error" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include("This lottery is not in draft state")
      end
    end

    context "when topic does not exist" do
      it "returns not found" do
        put "/vzekc-verlosung/lotteries/999999/publish.json"

        expect(response.status).to eq(404)
      end
    end
  end

  describe "#publish" do
    context "when user is not logged in" do
      let!(:lottery_result) do
        VzekcVerlosung::CreateLottery.call(
          params: {
            title: "Test Lottery",
            category_id: category.id,
            duration_days: 14,
            has_abholerpaket: false,
            packets: [{ title: "Packet 1" }],
          },
          user: user,
          guardian: Guardian.new(user),
        )
      end
      let(:topic) { lottery_result.main_topic }

      it "returns forbidden" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(403)
      end
    end
  end

  describe "#draw" do
    before { sign_in(user) }

    fab!(:other_user, :user)
    fab!(:admin)
    let!(:lottery_result) do
      VzekcVerlosung::CreateLottery.call(
        params: {
          title: "Test Lottery",
          category_id: category.id,
          duration_days: 14,
          has_abholerpaket: false,
          packets: [{ title: "Hardware Bundle" }],
        },
        user: user,
        guardian: Guardian.new(user),
      )
    end
    let(:topic) { lottery_result.main_topic }
    let(:lottery) { lottery_result.lottery }
    let(:packet_post) { lottery.lottery_packets.first.post }

    before do
      # Publish lottery and set it to ended
      lottery.update!(state: "active", ends_at: 1.day.ago)

      # Add a ticket
      VzekcVerlosung::LotteryTicket.create!(post_id: packet_post.id, user_id: user.id)
    end

    let(:valid_results) do
      # Get actual results from JavaScriptLotteryDrawer
      drawing_data = {
        "title" => topic.title,
        "timestamp" => (lottery.ends_at - 2.weeks).iso8601,
        "packets" => [
          {
            "id" => packet_post.id,
            "title" => "Hardware Bundle",
            "participants" => [{ "name" => user.username, "tickets" => 1 }],
          },
        ],
      }
      VzekcVerlosung::JavascriptLotteryDrawer.draw(drawing_data)
    end

    context "when results are valid" do
      it "accepts and stores verified results" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(204)
        lottery.reload
        expect(lottery.results).to be_present
        expect(lottery.state).to eq("finished")
        expect(lottery.drawn_at).to be_present
      end

      it "stores winner on packet post" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        lottery_packet = lottery.lottery_packets.first
        lottery_packet.reload
        expect(lottery_packet.winner&.username).to eq(user.username)
      end
    end

    context "when results are tampered with" do
      it "rejects results with wrong seed" do
        tampered_results = valid_results.dup
        tampered_results["rngSeed"] = "fakeseed123"

        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json",
             params: {
               results: tampered_results,
             }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(/verification failed/)
        lottery.reload
        expect(lottery.results).to be_nil
      end

      it "rejects results with wrong winner" do
        tampered_results = valid_results.dup
        tampered_results["drawings"][0]["winner"] = "fake_user"

        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json",
             params: {
               results: tampered_results,
             }

        expect(response.status).to eq(422)
        lottery.reload
        expect(lottery.results).to be_nil
      end
    end

    context "when user is staff" do
      before { sign_in(admin) }

      it "allows staff to draw" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(204)
      end
    end

    context "when user is not the owner" do
      before { sign_in(other_user) }

      it "returns forbidden" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(403)
      end
    end

    context "when lottery is already drawn" do
      before { lottery.mark_drawn!(valid_results) }

      it "returns error" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(/already been drawn/)
      end
    end
  end

  describe "#draw" do
    context "when user is not logged in" do
      let!(:lottery_result) do
        VzekcVerlosung::CreateLottery.call(
          params: {
            title: "Test Lottery",
            category_id: category.id,
            duration_days: 14,
            has_abholerpaket: false,
            packets: [{ title: "Hardware Bundle" }],
          },
          user: user,
          guardian: Guardian.new(user),
        )
      end
      let(:topic) { lottery_result.main_topic }
      let(:lottery) { lottery_result.lottery }
      let(:packet_post) { lottery.lottery_packets.first.post }

      before do
        # Publish lottery and set it to ended
        lottery.update!(state: "active", ends_at: 1.day.ago)

        # Add a ticket
        VzekcVerlosung::LotteryTicket.create!(post_id: packet_post.id, user_id: user.id)
      end

      let(:valid_results) do
        # Get actual results from JavaScriptLotteryDrawer
        drawing_data = {
          "title" => topic.title,
          "timestamp" => (lottery.ends_at - 2.weeks).iso8601,
          "packets" => [
            {
              "id" => packet_post.id,
              "title" => "Hardware Bundle",
              "participants" => [{ "name" => user.username, "tickets" => 1 }],
            },
          ],
        }
        VzekcVerlosung::JavascriptLotteryDrawer.draw(drawing_data)
      end

      it "returns forbidden" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(403)
      end
    end
  end

  describe "#draw_manual" do
    before { sign_in(user) }

    fab!(:other_user, :user)
    fab!(:admin)
    let!(:lottery_result) do
      VzekcVerlosung::CreateLottery.call(
        params: {
          title: "Manual Test Lottery",
          category_id: category.id,
          duration_days: 14,
          drawing_mode: "manual",
          has_abholerpaket: false,
          packets: [{ title: "Packet 1" }],
        },
        user: user,
        guardian: Guardian.new(user),
      )
    end
    let(:topic) { lottery_result.main_topic }
    let(:lottery) { lottery_result.lottery }
    let(:packet_post) { lottery.lottery_packets.first.post }

    before do
      # Publish lottery and set it to ended
      lottery.update!(state: "active", ends_at: 1.day.ago)

      # Add tickets
      VzekcVerlosung::LotteryTicket.create!(post_id: packet_post.id, user_id: user.id)
      VzekcVerlosung::LotteryTicket.create!(post_id: packet_post.id, user_id: other_user.id)
    end

    context "with valid selections" do
      it "accepts manual winner selections" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        expect(response.status).to eq(204)
        lottery.reload
        expect(lottery.results).to be_present
        expect(lottery.state).to eq("finished")
        expect(lottery.drawn_at).to be_present
      end

      it "marks winner on packet" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        lottery_packet = lottery.lottery_packets.first
        lottery_packet.reload
        expect(lottery_packet.winner&.id).to eq(user.id)
      end

      it "stores results with manual flag" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        lottery.reload
        expect(lottery.results["manual"]).to be true
        expect(lottery.results["drawings"]).to be_present
      end
    end

    context "with invalid selections" do
      it "returns error when missing winner for packet with participants" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json", params: { selections: {} }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(match(/Missing winner selection/))
      end

      it "returns error when selected user is not a participant" do
        non_participant = Fabricate(:user)

        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => non_participant.id,
               },
             }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(match(/not a participant/))
      end
    end

    context "when lottery is automatic mode" do
      before { lottery.update!(drawing_mode: "automatic") }

      it "returns error" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(match(/automatic drawing mode/))
      end
    end

    context "when user is staff" do
      before { sign_in(admin) }

      it "allows staff to draw manually" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        expect(response.status).to eq(204)
      end
    end

    context "when user is not the owner" do
      before { sign_in(other_user) }

      it "returns forbidden" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        expect(response.status).to eq(403)
      end
    end

    context "when lottery is already drawn" do
      before do
        lottery.mark_drawn!({ manual: true, drawings: [{ text: "Packet 1", winner: user.username }] })
      end

      it "returns error" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw-manual.json",
             params: {
               selections: {
                 packet_post.id.to_s => user.id,
               },
             }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(match(/already been drawn/))
      end
    end
  end
end
