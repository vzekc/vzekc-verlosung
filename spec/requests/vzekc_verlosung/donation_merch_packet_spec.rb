# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::DonationsController do
  fab!(:user)
  fab!(:other_user, :user)
  fab!(:donation) { Fabricate(:donation, creator_user_id: user.id, state: "picked_up") }

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#create_merch_packet" do
    let(:valid_params) do
      {
        donor_name: "Max Mustermann",
        donor_street: "Musterstraße",
        donor_street_number: "42",
        donor_postcode: "12345",
        donor_city: "Musterstadt",
      }
    end

    context "when not logged in" do
      it "returns 403" do
        post "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json", params: valid_params
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as non-facilitator" do
      before { sign_in(other_user) }

      it "returns 403" do
        post "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json", params: valid_params
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as facilitator" do
      before { sign_in(user) }

      it "creates a merch packet" do
        post "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json", params: valid_params
        expect(response.status).to eq(201)

        json = response.parsed_body
        expect(json["merch_packet"]["donor_name"]).to eq("Max Mustermann")
        expect(json["merch_packet"]["state"]).to eq("pending")
      end

      it "returns 422 when donation already has a merch packet" do
        Fabricate(:merch_packet, donation: donation)
        post "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json", params: valid_params
        expect(response.status).to eq(422)
      end

      it "returns 422 with invalid params" do
        post "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json",
             params: {
               donor_name: "Max",
             }
        expect(response.status).to eq(422)
      end
    end
  end

  describe "#update_merch_packet" do
    let!(:merch_packet) { Fabricate(:merch_packet, donation: donation) }

    context "when logged in as facilitator" do
      before { sign_in(user) }

      it "updates the merch packet" do
        put "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json",
            params: {
              donor_name: "New Name",
            }
        expect(response.status).to eq(204)

        merch_packet.reload
        expect(merch_packet.donor_name).to eq("New Name")
      end

      it "returns 422 when packet is already shipped" do
        merch_packet.update!(state: "shipped", shipped_at: Time.zone.now)
        put "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json",
            params: {
              donor_name: "New Name",
            }
        expect(response.status).to eq(422)
      end
    end

    context "when logged in as non-facilitator" do
      before { sign_in(other_user) }

      it "returns 403" do
        put "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json",
            params: {
              donor_name: "New Name",
            }
        expect(response.status).to eq(403)
      end
    end
  end

  describe "#destroy_merch_packet" do
    let!(:merch_packet) { Fabricate(:merch_packet, donation: donation) }

    context "when logged in as facilitator" do
      before { sign_in(user) }

      it "deletes the merch packet" do
        delete "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json"
        expect(response.status).to eq(204)
        expect(donation.reload.merch_packet).to be_nil
      end

      it "returns 422 when packet is already shipped" do
        merch_packet.update!(state: "shipped", shipped_at: Time.zone.now)
        delete "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json"
        expect(response.status).to eq(422)
      end
    end

    context "when logged in as non-facilitator" do
      before { sign_in(other_user) }

      it "returns 403" do
        delete "/vzekc-verlosung/donations/#{donation.id}/merch-packet.json"
        expect(response.status).to eq(403)
      end
    end
  end
end
