# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::LotteryInterestsController do
  fab!(:facilitator, :user)
  fab!(:user)
  fab!(:topic) { Fabricate(:topic, user: facilitator) }
  fab!(:donation) do
    VzekcVerlosung::Donation.create!(
      postcode: "12345",
      creator_user_id: facilitator.id,
      state: "open",
      topic_id: topic.id,
      published_at: Time.zone.now,
    )
  end

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#create" do
    context "when user is not logged in" do
      it "returns 403" do
        post "/vzekc-verlosung/donations/#{donation.id}/lottery-interests.json"
        expect(response.status).to eq(403)
      end
    end

    context "when user is logged in" do
      before { sign_in(user) }

      it "creates a lottery interest" do
        expect {
          post "/vzekc-verlosung/donations/#{donation.id}/lottery-interests.json"
        }.to change { VzekcVerlosung::LotteryInterest.count }.by(1)

        expect(response.status).to eq(200)
        json = response.parsed_body
        expect(json["success"]).to eq("OK")
        expect(json["interest"]["user"]["id"]).to eq(user.id)
      end

      it "notifies the facilitator" do
        expect {
          post "/vzekc-verlosung/donations/#{donation.id}/lottery-interests.json"
        }.to change { VzekcVerlosung::NotificationLog.count }.by(1)

        log = VzekcVerlosung::NotificationLog.last
        expect(log.notification_type).to eq("new_lottery_interest")
        expect(log.recipient_user_id).to eq(facilitator.id)
      end

      context "when user already has an interest" do
        before do
          VzekcVerlosung::LotteryInterest.create!(donation_id: donation.id, user_id: user.id)
        end

        it "returns forbidden" do
          post "/vzekc-verlosung/donations/#{donation.id}/lottery-interests.json"
          expect(response.status).to eq(403)
        end
      end

      context "when donation is not open" do
        before { donation.update!(state: "assigned") }

        it "returns forbidden" do
          post "/vzekc-verlosung/donations/#{donation.id}/lottery-interests.json"
          expect(response.status).to eq(403)
        end
      end
    end
  end

  describe "#destroy" do
    let!(:interest) do
      VzekcVerlosung::LotteryInterest.create!(donation_id: donation.id, user_id: user.id)
    end

    context "when user is not logged in" do
      it "returns 403" do
        delete "/vzekc-verlosung/lottery-interests/#{interest.id}.json"
        expect(response.status).to eq(403)
      end
    end

    context "when user is logged in" do
      before { sign_in(user) }

      it "deletes the interest" do
        expect { delete "/vzekc-verlosung/lottery-interests/#{interest.id}.json" }.to change {
          VzekcVerlosung::LotteryInterest.count
        }.by(-1)

        expect(response.status).to eq(204)
      end
    end

    context "when another user tries to delete" do
      fab!(:other_user, :user)

      before { sign_in(other_user) }

      it "returns forbidden" do
        delete "/vzekc-verlosung/lottery-interests/#{interest.id}.json"
        expect(response.status).to eq(403)
      end
    end
  end

  describe "#index" do
    before do
      sign_in(user)
      VzekcVerlosung::LotteryInterest.create!(donation_id: donation.id, user_id: user.id)
    end

    it "returns lottery interests for a donation" do
      get "/vzekc-verlosung/donations/#{donation.id}/lottery-interests.json"

      expect(response.status).to eq(200)
      json = response.parsed_body
      expect(json["interests"].length).to eq(1)
      expect(json["interests"][0]["user"]["id"]).to eq(user.id)
    end
  end
end
