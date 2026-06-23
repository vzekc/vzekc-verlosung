# frozen_string_literal: true

RSpec.describe VzekcVerlosung::PickupOffersController do
  fab!(:facilitator) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:picker1, :user)
  fab!(:picker2, :user)
  fab!(:topic) { Fabricate(:topic, user: facilitator) }
  fab!(:donation) do
    Fabricate(:donation, creator_user_id: facilitator.id, state: "open", topic_id: topic.id)
  end

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#index" do
    it "includes the collected_count for each offerer" do
      Fabricate(:pickup_offer, donation: donation, user: picker1)
      previous = Fabricate(:donation, creator_user_id: facilitator.id)
      Fabricate(:pickup_offer, donation: previous, user: picker1, state: "picked_up")

      sign_in(facilitator)
      get "/vzekc-verlosung/donations/#{donation.id}/pickup-offers.json"

      expect(response.status).to eq(200)
      offer = response.parsed_body["offers"].first
      expect(offer["user"]["collected_count"]).to eq(1)
    end
  end

  describe "#assign" do
    it "posts a response authored by the facilitator naming the picker" do
      offer = Fabricate(:pickup_offer, donation: donation, user: picker1)

      sign_in(facilitator)
      expect {
        put "/vzekc-verlosung/pickup-offers/#{offer.id}/assign.json",
            params: {
              contact_info: "Bitte den Spender unter 0123456789 anrufen",
            }
      }.to change { topic.posts.count }.by(1)

      expect(response.status).to eq(204)
      post = topic.posts.order(:post_number).last
      expect(post.user_id).to eq(facilitator.id)
      expect(post.raw).to include("@#{picker1.username}")
    end

    context "when the choice diverges from the fewest-collections rule" do
      before do
        previous = Fabricate(:donation, creator_user_id: facilitator.id)
        Fabricate(:pickup_offer, donation: previous, user: picker1, state: "picked_up")
        Fabricate(:pickup_offer, donation: donation, user: picker1)
        Fabricate(:pickup_offer, donation: donation, user: picker2)
      end

      it "rejects assignment without an explanation" do
        offer = donation.pickup_offers.find_by(user_id: picker1.id)

        sign_in(facilitator)
        put "/vzekc-verlosung/pickup-offers/#{offer.id}/assign.json",
            params: {
              contact_info: "Bitte den Spender unter 0123456789 anrufen",
            }

        expect(response.status).to eq(422)
        donation.reload
        expect(donation.state).to eq("open")
      end

      it "includes the explanation in the post when provided" do
        offer = donation.pickup_offers.find_by(user_id: picker1.id)

        sign_in(facilitator)
        put "/vzekc-verlosung/pickup-offers/#{offer.id}/assign.json",
            params: {
              contact_info: "Bitte den Spender unter 0123456789 anrufen",
              explanation: "picker1 wohnt nebenan",
            }

        expect(response.status).to eq(204)
        post = topic.posts.order(:post_number).last
        expect(post.user_id).to eq(facilitator.id)
        expect(post.raw).to include("picker1 wohnt nebenan")
      end
    end
  end

  describe "#auto_assign" do
    it "assigns to the picker with the fewest collections and posts a response" do
      previous = Fabricate(:donation, creator_user_id: facilitator.id)
      Fabricate(:pickup_offer, donation: previous, user: picker2, state: "picked_up")
      Fabricate(:pickup_offer, donation: donation, user: picker1)
      Fabricate(:pickup_offer, donation: donation, user: picker2)

      sign_in(facilitator)
      put "/vzekc-verlosung/donations/#{donation.id}/auto-assign.json",
          params: {
            contact_info: "Bitte den Spender unter 0123456789 anrufen",
          }

      expect(response.status).to eq(204)
      donation.reload
      expect(donation.state).to eq("assigned")
      assigned = donation.pickup_offers.find_by(state: "assigned")
      expect(assigned.user_id).to eq(picker1.id)
      post = topic.posts.order(:post_number).last
      expect(post.user_id).to eq(Discourse.system_user.id)
      expect(post.raw).to include("@#{picker1.username}")
    end

    it "requires contact information" do
      Fabricate(:pickup_offer, donation: donation, user: picker1)

      sign_in(facilitator)
      put "/vzekc-verlosung/donations/#{donation.id}/auto-assign.json", params: { contact_info: "" }

      expect(response.status).to eq(422)
      donation.reload
      expect(donation.state).to eq("open")
    end

    it "forbids users who do not manage the donation" do
      Fabricate(:pickup_offer, donation: donation, user: picker1)

      sign_in(picker2)
      put "/vzekc-verlosung/donations/#{donation.id}/auto-assign.json",
          params: {
            contact_info: "Some contact information here",
          }

      expect(response.status).to eq(403)
    end

    it "rejects assignment when the donation is not open" do
      donation.update!(state: "assigned")
      Fabricate(:pickup_offer, donation: donation, user: picker1)

      sign_in(facilitator)
      put "/vzekc-verlosung/donations/#{donation.id}/auto-assign.json",
          params: {
            contact_info: "Some contact information here",
          }

      expect(response.status).to eq(422)
    end

    it "rejects auto-assignment when there are no pending offers" do
      sign_in(facilitator)
      put "/vzekc-verlosung/donations/#{donation.id}/auto-assign.json",
          params: {
            contact_info: "Some contact information here",
          }

      expect(response.status).to eq(422)
    end
  end
end
