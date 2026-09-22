# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::DonationsController do
  fab!(:facilitator, :user)
  fab!(:other_user, :user)

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#create" do
    let(:address_params) do
      {
        postcode: "10115",
        donor_name: "Max Mustermann",
        donor_street: "Musterstraße",
        donor_street_number: "42",
        donor_postcode: "12345",
        donor_city: "Musterstadt",
      }
    end

    before { sign_in(facilitator) }

    it "creates the merch packet with the donor's email" do
      post "/vzekc-verlosung/donations.json",
           params: address_params.merge(donor_email: "max@example.com")

      expect(response.status).to eq(200)
      donation = VzekcVerlosung::Donation.find(response.parsed_body["donation_id"])
      expect(donation.merch_packet.donor_email).to eq("max@example.com")
    end

    it "returns 422 when the donor's email is missing" do
      expect { post "/vzekc-verlosung/donations.json", params: address_params }.not_to change {
        VzekcVerlosung::Donation.count
      }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("vzekc_verlosung.errors.donor_email_required"),
      )
    end

    it "creates a donation without a merch packet when no donor data is given" do
      post "/vzekc-verlosung/donations.json", params: { postcode: "10115" }

      expect(response.status).to eq(200)
      donation = VzekcVerlosung::Donation.find(response.parsed_body["donation_id"])
      expect(donation.merch_packet).to be_nil
    end
  end

  describe "#show" do
    fab!(:donation) { Fabricate(:donation, creator_user_id: facilitator.id, state: "open") }
    fab!(:merch_packet) do
      Fabricate(:merch_packet, donation: donation, donor_email: "max@example.com")
    end

    context "as the facilitator" do
      before { sign_in(facilitator) }

      it "includes the donor's name and email" do
        get "/vzekc-verlosung/donations/#{donation.id}.json"

        expect(response.status).to eq(200)
        expect(response.parsed_body["donation"]["donor_contact"]).to eq(
          "name" => "Max Mustermann",
          "email" => "max@example.com",
        )
      end

      it "omits the donor contact once the merch packet is archived" do
        merch_packet.update!(state: "shipped", shipped_at: 5.weeks.ago)
        merch_packet.archive!

        get "/vzekc-verlosung/donations/#{donation.id}.json"

        expect(response.parsed_body["donation"]["donor_contact"]).to be_nil
      end
    end

    context "as another user" do
      before { sign_in(other_user) }

      it "omits the donor contact" do
        get "/vzekc-verlosung/donations/#{donation.id}.json"

        expect(response.status).to eq(200)
        expect(response.parsed_body["donation"]["donor_contact"]).to be_nil
      end
    end
  end
end
