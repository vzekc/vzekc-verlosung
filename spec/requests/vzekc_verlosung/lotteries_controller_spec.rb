# frozen_string_literal: true

RSpec.describe VzekcVerlosung::LotteriesController do
  fab!(:user)
  fab!(:category)

  before { sign_in(user) }

  describe "#create" do
    let(:valid_params) do
      {
        title: "Hardware Verlosung Januar 2025",
        description: "Eine tolle Verlosung",
        category_id: category.id,
        packets: [
          { title: "Packet 1", description: "Inhalt 1" },
          { title: "Packet 2", description: "Inhalt 2" },
        ],
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
        expect {
          post "/vzekc-verlosung/lotteries.json", params: valid_params
        }.to change { Topic.count }.by(3)
      end

      it "returns main topic details" do
        post "/vzekc-verlosung/lotteries.json", params: valid_params

        json = response.parsed_body
        expect(json["main_topic"]["title"]).to eq("Hardware Verlosung Januar 2025")
        expect(json["main_topic"]["id"]).to be_present
        expect(json["main_topic"]["url"]).to be_present
      end
    end

    context "when request is invalid" do
      it "returns error for missing title" do
        invalid_params = valid_params.merge(title: "")
        post "/vzekc-verlosung/lotteries.json", params: invalid_params

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["success"]).to eq("FAILED")
        expect(json["errors"]).to be_present
      end

      it "returns error for empty packets" do
        invalid_params = valid_params.merge(packets: [])
        post "/vzekc-verlosung/lotteries.json", params: invalid_params

        expect(response.status).to eq(422)
      end
    end

    context "when user is not logged in" do
      before { sign_out }

      it "returns forbidden" do
        post "/vzekc-verlosung/lotteries.json", params: valid_params

        expect(response.status).to eq(403)
      end
    end
  end

  describe "#publish" do
    fab!(:other_user) { Fabricate(:user) }
    fab!(:admin) { Fabricate(:admin) }
    let!(:lottery_result) do
      VzekcVerlosung::CreateLottery.call(
        params: {
          title: "Test Lottery",
          description: "Test description",
          category_id: category.id,
          packets: [{ title: "Packet 1", description: "Content" }],
        },
        user: user,
        guardian: Guardian.new(user),
      )
    end
    let(:topic) { lottery_result.main_topic }

    context "when user is the topic owner" do
      it "publishes the lottery" do
        expect(topic.custom_fields["lottery_state"]).to eq("draft")

        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(204)
        topic.reload
        expect(topic.custom_fields["lottery_state"]).to eq("active")
        expect(topic.custom_fields["lottery_ends_at"]).to be_present
      end
    end

    context "when user is staff" do
      before { sign_in(admin) }

      it "allows staff to publish" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(204)
        topic.reload
        expect(topic.custom_fields["lottery_state"]).to eq("active")
        expect(topic.custom_fields["lottery_ends_at"]).to be_present
      end
    end

    context "when user is not the owner" do
      before { sign_in(other_user) }

      it "returns forbidden" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(403)
        topic.reload
        expect(topic.custom_fields["lottery_state"]).to eq("draft")
      end
    end

    context "when topic is already published" do
      before do
        topic.custom_fields["lottery_state"] = "active"
        topic.save_custom_fields
      end

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

    context "when user is not logged in" do
      before { sign_out }

      it "returns forbidden" do
        put "/vzekc-verlosung/lotteries/#{topic.id}/publish.json"

        expect(response.status).to eq(403)
      end
    end
  end

  describe "#draw" do
    fab!(:other_user) { Fabricate(:user) }
    fab!(:admin) { Fabricate(:admin) }
    let!(:lottery_result) do
      VzekcVerlosung::CreateLottery.call(
        params: {
          title: "Test Lottery",
          description: "Test description",
          category_id: category.id,
          packets: [{ title: "Hardware Bundle", description: "Content" }],
        },
        user: user,
        guardian: Guardian.new(user),
      )
    end
    let(:topic) { lottery_result.main_topic }
    let(:packet_post) { lottery_result.packet_topics.first.posts.first }

    before do
      # Publish lottery and set it to ended
      topic.custom_fields["lottery_state"] = "active"
      topic.custom_fields["lottery_ends_at"] = 1.day.ago
      topic.save_custom_fields

      # Add a ticket
      VzekcVerlosung::LotteryTicket.create!(post_id: packet_post.id, user_id: user.id)
    end

    let(:valid_results) do
      # Get actual results from JavaScriptLotteryDrawer
      drawing_data = {
        "title" => topic.title,
        "timestamp" => (topic.lottery_ends_at - 2.weeks).iso8601,
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
        topic.reload
        expect(topic.custom_fields["lottery_results"]).to be_present
        expect(topic.custom_fields["lottery_state"]).to eq("finished")
        expect(topic.custom_fields["lottery_drawn_at"]).to be_present
      end

      it "stores winner on packet post" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        packet_post.reload
        expect(packet_post.custom_fields["lottery_winner"]).to eq(user.username)
      end
    end

    context "when results are tampered with" do
      it "rejects results with wrong seed" do
        tampered_results = valid_results.dup
        tampered_results["rngSeed"] = "fakeseed123"

        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: tampered_results }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(/verification failed/)
        topic.reload
        expect(topic.custom_fields["lottery_results"]).to be_nil
      end

      it "rejects results with wrong winner" do
        tampered_results = valid_results.dup
        tampered_results["drawings"][0]["winner"] = "fake_user"

        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: tampered_results }

        expect(response.status).to eq(422)
        topic.reload
        expect(topic.custom_fields["lottery_results"]).to be_nil
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
      before do
        topic.custom_fields["lottery_results"] = valid_results
        topic.save_custom_fields
      end

      it "returns error" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(422)
        json = response.parsed_body
        expect(json["errors"]).to include(/already been drawn/)
      end
    end

    context "when user is not logged in" do
      before { sign_out }

      it "returns forbidden" do
        post "/vzekc-verlosung/lotteries/#{topic.id}/draw.json", params: { results: valid_results }

        expect(response.status).to eq(403)
      end
    end
  end
end
