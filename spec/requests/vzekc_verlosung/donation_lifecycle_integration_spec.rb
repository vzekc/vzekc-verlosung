# frozen_string_literal: true

RSpec.describe "Donation Full Lifecycle Integration" do
  fab!(:facilitator) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:picker1) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:picker2) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:picker3) { Fabricate(:user, trust_level: TrustLevel[1]) }
  fab!(:donations_category) { Fabricate(:category, name: "Spendenangebote") }
  fab!(:erhaltungsberichte_category) { Fabricate(:category, name: "Erhaltungsberichte") }
  fab!(:lotteries_category) { Fabricate(:category, name: "Verlosungen") }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    # CRITICAL: Set as strings to match production behavior (SiteSettings are always strings)
    SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = erhaltungsberichte_category.id.to_s
    SiteSetting.vzekc_verlosung_category_id = lotteries_category.id.to_s
  end

  describe "Path 1: Donation → Pickup → Erhaltungsbericht" do
    it "completes full lifecycle from draft to Erhaltungsbericht with proper topic linking" do
      # STEP 1: Create donation in draft state
      freeze_time(Time.zone.parse("2025-01-15 10:00:00"))

      sign_in(facilitator)
      post "/vzekc-verlosung/donations.json", params: { postcode: "10115" }

      expect(response.status).to eq(200),
      "Expected 200 but got #{response.status}: #{response.body}"
      donation_id = response.parsed_body["donation_id"]
      expect(donation_id).to be_present

      donation = VzekcVerlosung::Donation.find(donation_id)
      expect(donation.state).to eq("draft")
      expect(donation.postcode).to eq("10115")
      expect(donation.creator_user_id).to eq(facilitator.id)
      expect(donation.topic_id).to be_nil # No topic yet

      # STEP 2: Create topic for donation via composer
      # Simulate what the frontend does when publishing
      post "/posts.json",
           params: {
             title: "Hardware in Berlin 10115",
             raw: "Ich habe Hardware zu verschenken",
             category: donations_category.id,
             donation_id: donation_id, # Serialized by donation-composer.js
           }

      expect(response.status).to eq(200), "Post creation failed: #{response.body}"
      donation_topic = Topic.find(response.parsed_body["topic_id"])
      expect(donation_topic.category_id).to eq(donations_category.id)

      # CRITICAL: Verify donation is linked to topic AND auto-published
      # The topic_created hook automatically links and publishes
      donation.reload
      expect(donation.topic_id).to eq(donation_topic.id)
      expect(donation.erhaltungsbericht_topic_id).to be_nil # Should NOT be set!
      expect(donation.state).to eq("open") # Auto-published by hook
      expect(donation.published_at).to be_within(1.minute).of(Time.zone.now)

      # STEP 3: Three users offer to pick up
      freeze_time(Time.zone.parse("2025-01-16 14:00:00"))

      sign_in(picker1)
      post "/vzekc-verlosung/donations/#{donation_id}/pickup-offers.json"
      expect(response.status).to eq(200)
      offer1_id = response.parsed_body["offer"]["id"]

      sign_in(picker2)
      post "/vzekc-verlosung/donations/#{donation_id}/pickup-offers.json"
      expect(response.status).to eq(200)
      offer2_id = response.parsed_body["offer"]["id"]

      sign_in(picker3)
      post "/vzekc-verlosung/donations/#{donation_id}/pickup-offers.json"
      expect(response.status).to eq(200)
      offer3_id = response.parsed_body["offer"]["id"]

      # Verify all offers
      offers = VzekcVerlosung::PickupOffer.where(donation_id: donation_id)
      expect(offers.count).to eq(3)
      expect(offers.pluck(:state).uniq).to eq(["pending"])

      # STEP 4: Picker2 retracts their offer
      freeze_time(Time.zone.parse("2025-01-17 09:00:00"))

      sign_in(picker2)
      delete "/vzekc-verlosung/pickup-offers/#{offer2_id}.json"
      expect(response.status).to eq(204)

      # Verify offer was deleted
      expect(VzekcVerlosung::PickupOffer.exists?(offer2_id)).to be false
      expect(VzekcVerlosung::PickupOffer.where(donation_id: donation_id).count).to eq(2)

      # STEP 5: Facilitator assigns picker1
      freeze_time(Time.zone.parse("2025-01-18 10:00:00"))

      sign_in(facilitator)
      put "/vzekc-verlosung/pickup-offers/#{offer1_id}/assign.json",
          params: {
            contact_info: "Contact donor at +49123456789",
          }
      expect(response.status).to eq(204)

      # Verify assignment
      donation.reload
      expect(donation.state).to eq("assigned")

      offer1 = VzekcVerlosung::PickupOffer.find(offer1_id)
      expect(offer1.state).to eq("assigned")
      expect(offer1.assigned_at).to be_within(1.minute).of(Time.zone.now)

      # Verify other offers still pending
      offer3 = VzekcVerlosung::PickupOffer.find(offer3_id)
      expect(offer3.state).to eq("pending")

      # STEP 6: Picker1 marks as picked up
      freeze_time(Time.zone.parse("2025-01-20 15:00:00"))

      sign_in(picker1)
      put "/vzekc-verlosung/pickup-offers/#{offer1_id}/mark-picked-up.json"
      expect(response.status).to eq(204)

      # Verify pickup - donation auto-closes after pickup
      donation.reload
      expect(donation.state).to eq("closed") # Auto-closed by close_automatically!

      offer1.reload
      expect(offer1.state).to eq("picked_up")
      expect(offer1.picked_up_at).to be_within(1.minute).of(Time.zone.now)

      # STEP 7: Picker1 creates Erhaltungsbericht
      freeze_time(Time.zone.parse("2025-01-22 11:00:00"))

      sign_in(picker1)
      post "/posts.json",
           params: {
             title: "Erhaltungsbericht: Hardware in Berlin 10115",
             raw: "Das System läuft super!",
             category: erhaltungsberichte_category.id,
             erhaltungsbericht_donation_id: donation_id, # Serialized by erhaltungsbericht-composer.js
           }

      expect(response.status).to eq(200)
      erhaltungsbericht_topic = Topic.find(response.parsed_body["topic_id"])

      # CRITICAL: Verify bidirectional linking between donation and Erhaltungsbericht topic
      donation.reload
      expect(donation.erhaltungsbericht_topic_id).to eq(erhaltungsbericht_topic.id)
      expect(donation.erhaltungsbericht_topic_id).not_to eq(donation.topic_id) # NOT the donation topic!

      # Verify custom field for UI (stored as integer due to register_topic_custom_field_type)
      expect(erhaltungsbericht_topic.custom_fields["donation_id"]).to eq(donation_id)

      # STEP 8: Verify donation shows Erhaltungsbericht in API
      get "/vzekc-verlosung/donations/#{donation_id}.json"
      expect(response.status).to eq(200)

      donation_data = response.parsed_body["donation"]
      expect(donation_data["erhaltungsbericht"]).to be_present
      expect(donation_data["erhaltungsbericht"]["id"]).to eq(erhaltungsbericht_topic.id)
      expect(donation_data["erhaltungsbericht"]["url"]).to eq(erhaltungsbericht_topic.url)

      # CRITICAL: Verify no lottery was created
      expect(donation.lottery).to be_nil
      expect(donation_data["lottery"]).to be_nil
    end
  end

  describe "Path 2: Donation → Pickup → Lottery" do
    it "completes lifecycle from draft to lottery with proper linking" do
      # STEP 1-6: Same as Path 1 up to pickup
      freeze_time(Time.zone.parse("2025-01-15 10:00:00"))

      sign_in(facilitator)
      post "/vzekc-verlosung/donations.json", params: { postcode: "12345" }
      donation_id = response.parsed_body["donation_id"]

      # Create and auto-publish donation topic
      post "/posts.json",
           params: {
             title: "Hardware in 12345",
             raw: "Zu verschenken",
             category: donations_category.id,
             donation_id: donation_id,
           }

      sign_in(picker1)
      post "/vzekc-verlosung/donations/#{donation_id}/pickup-offers.json"
      offer_id = response.parsed_body["offer"]["id"]

      sign_in(facilitator)
      put "/vzekc-verlosung/pickup-offers/#{offer_id}/assign.json",
          params: {
            contact_info: "Contact info",
          }

      sign_in(picker1)
      put "/vzekc-verlosung/pickup-offers/#{offer_id}/mark-picked-up.json"

      # STEP 7: Picker1 creates lottery from donation
      freeze_time(Time.zone.parse("2025-01-22 11:00:00"))

      sign_in(picker1)
      post "/vzekc-verlosung/lotteries.json",
           params: {
             title: "Hardware Verlosung aus Spende",
             raw: "Lottery content",
             category_id: lotteries_category.id,
             duration_days: 7,
             packets: [
               { title: "GPU Paket", raw: "GPU content" },
               { title: "RAM Paket", raw: "RAM content" },
             ],
             donation_id: donation_id, # Link to donation
           }

      expect(response.status).to eq(200)
      lottery_topic = Topic.find(response.parsed_body["main_topic"]["id"])

      # CRITICAL: Verify bidirectional linking between donation and lottery
      donation = VzekcVerlosung::Donation.find(donation_id)
      lottery = VzekcVerlosung::Lottery.find_by(topic_id: lottery_topic.id)

      expect(lottery).to be_present
      expect(lottery.donation_id).to eq(donation_id)
      expect(donation.lottery).to eq(lottery)

      # Verify lottery topic is different from donation topic
      expect(lottery.topic_id).not_to eq(donation.topic_id)

      # STEP 8: Verify donation shows lottery in API
      get "/vzekc-verlosung/donations/#{donation_id}.json"
      expect(response.status).to eq(200)

      donation_data = response.parsed_body["donation"]
      expect(donation_data["lottery"]).to be_present
      expect(donation_data["lottery"]["id"]).to eq(lottery.id)
      expect(donation_data["lottery"]["url"]).to eq(lottery_topic.url)

      # CRITICAL: Verify no Erhaltungsbericht was created
      expect(donation.erhaltungsbericht_topic_id).to be_nil
      expect(donation_data["erhaltungsbericht"]).to be_nil
    end
  end

  describe "Edge Cases" do
    it "prevents setting erhaltungsbericht_topic_id to donation's own topic" do
      # This tests the fix for the bug where donation topic creation
      # incorrectly set erhaltungsbericht_topic_id

      sign_in(facilitator)
      post "/vzekc-verlosung/donations.json", params: { postcode: "99999" }
      donation_id = response.parsed_body["donation_id"]

      # Create donation topic with donation_id in opts
      post "/posts.json",
           params: {
             title: "Test Donation",
             raw: "Test content",
             category: donations_category.id,
             donation_id: donation_id,
           }

      donation_topic_id = response.parsed_body["topic_id"]

      # CRITICAL: Verify erhaltungsbericht_topic_id is NOT set to own topic
      donation = VzekcVerlosung::Donation.find(donation_id)
      expect(donation.topic_id).to eq(donation_topic_id)
      expect(donation.erhaltungsbericht_topic_id).to be_nil # Correctly NOT set
    end

    it "validates exclusive outcome - cannot have both lottery and Erhaltungsbericht" do
      # This test verifies the model validation at app/models/vzekc_verlosung/donation.rb:36
      # A donation can have EITHER a lottery OR an Erhaltungsbericht, but not both

      donation =
        VzekcVerlosung::Donation.create!(
          postcode: "11111",
          creator_user_id: facilitator.id,
          state: "closed",
        )

      # Create lottery
      lottery =
        VzekcVerlosung::Lottery.create!(
          topic_id: Fabricate(:topic).id,
          state: "active",
          donation_id: donation.id,
        )

      donation.reload

      # Try to set erhaltungsbericht_topic_id - should fail validation
      erhaltungsbericht_topic = Fabricate(:topic)
      donation.erhaltungsbericht_topic_id = erhaltungsbericht_topic.id

      expect(donation.valid?).to be false
      expect(donation.errors[:base]).to include(
        "A donation cannot have both a lottery and an Erhaltungsbericht. Please choose one outcome.",
      )
    end

    it "allows offer retraction by owner" do
      sign_in(facilitator)
      post "/vzekc-verlosung/donations.json", params: { postcode: "22222" }
      donation_id = response.parsed_body["donation_id"]

      # Create and auto-publish
      post "/posts.json",
           params: {
             title: "Retraction Test",
             raw: "Content",
             category: donations_category.id,
             donation_id: donation_id,
           }

      sign_in(picker1)
      post "/vzekc-verlosung/donations/#{donation_id}/pickup-offers.json"
      offer_id = response.parsed_body["offer"]["id"]

      # Can retract own offer
      delete "/vzekc-verlosung/pickup-offers/#{offer_id}.json"
      expect(response.status).to eq(204)
      expect(VzekcVerlosung::PickupOffer.exists?(offer_id)).to be false

      # Create new offer
      post "/vzekc-verlosung/donations/#{donation_id}/pickup-offers.json"
      offer_id = response.parsed_body["offer"]["id"]

      # Cannot retract someone else's offer
      sign_in(picker2)
      delete "/vzekc-verlosung/pickup-offers/#{offer_id}.json"
      expect(response.status).to eq(403) # Forbidden
      expect(VzekcVerlosung::PickupOffer.exists?(offer_id)).to be true

      # NOTE: The backend currently allows retraction even when assigned.
      # The frontend prevents this via canRetractOffer, but backend validation would be better.
    end
  end
end
