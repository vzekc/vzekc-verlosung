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
end
