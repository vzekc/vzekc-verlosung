# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::MerchPacketsController do
  fab!(:user)
  fab!(:merch_handler, :user)
  fab!(:merch_handlers_group) { Fabricate(:group, name: "merch-handlers") }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_merch_handlers_group_name = "merch-handlers"
    merch_handlers_group.add(merch_handler)
  end

  describe "#index" do
    let!(:donation) { Fabricate(:donation, state: "picked_up") }
    let!(:pending_packet) { Fabricate(:merch_packet, donation: donation) }
    let!(:shipped_packet) do
      Fabricate(:merch_packet, donation: Fabricate(:donation, state: "picked_up"), state: "shipped", shipped_at: Time.zone.now)
    end

    context "when not logged in" do
      it "returns 403" do
        get "/vzekc-verlosung/merch-packets.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as regular user" do
      before { sign_in(user) }

      it "returns 403" do
        get "/vzekc-verlosung/merch-packets.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as merch handler" do
      before { sign_in(merch_handler) }

      it "returns merch packets" do
        get "/vzekc-verlosung/merch-packets.json"
        expect(response.status).to eq(200)

        json = response.parsed_body
        expect(json["merch_packets"].length).to eq(2)
      end

      it "excludes archived packets" do
        archived =
          Fabricate(
            :merch_packet,
            donation: Fabricate(:donation, state: "picked_up"),
            state: "archived",
            donor_name: nil,
            donor_street: nil,
            donor_street_number: nil,
            donor_postcode: nil,
            donor_city: nil,
          )
        get "/vzekc-verlosung/merch-packets.json"

        json = response.parsed_body
        packet_ids = json["merch_packets"].map { |p| p["id"] }
        expect(packet_ids).not_to include(archived.id)
      end

      it "includes packet details" do
        get "/vzekc-verlosung/merch-packets.json"

        json = response.parsed_body
        packet = json["merch_packets"].find { |p| p["id"] == pending_packet.id }
        expect(packet["state"]).to eq("pending")
        expect(packet["donor_name"]).to eq(pending_packet.donor_name)
        expect(packet["formatted_address"]).to be_present
      end
    end
  end

  describe "#ship" do
    let!(:donation) { Fabricate(:donation) }
    let!(:pending_packet) { Fabricate(:merch_packet, donation: donation) }

    context "when not logged in" do
      it "returns 403" do
        put "/vzekc-verlosung/merch-packets/#{pending_packet.id}/ship.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as regular user" do
      before { sign_in(user) }

      it "returns 403" do
        put "/vzekc-verlosung/merch-packets/#{pending_packet.id}/ship.json"
        expect(response.status).to eq(403)
      end
    end

    context "when logged in as merch handler" do
      before { sign_in(merch_handler) }

      it "marks packet as shipped" do
        put "/vzekc-verlosung/merch-packets/#{pending_packet.id}/ship.json"
        expect(response.status).to eq(204)

        pending_packet.reload
        expect(pending_packet.state).to eq("shipped")
        expect(pending_packet.shipped_at).to be_present
        expect(pending_packet.shipped_by_user).to eq(merch_handler)
      end

      it "stores tracking info if provided" do
        put "/vzekc-verlosung/merch-packets/#{pending_packet.id}/ship.json",
            params: {
              tracking_info: "DHL 123456789",
            }
        expect(response.status).to eq(204)

        pending_packet.reload
        expect(pending_packet.tracking_info).to eq("DHL 123456789")
      end

      it "returns error if packet already shipped" do
        pending_packet.update!(state: "shipped", shipped_at: Time.zone.now)

        put "/vzekc-verlosung/merch-packets/#{pending_packet.id}/ship.json"
        expect(response.status).to eq(422)
      end

      it "returns 404 for non-existent packet" do
        put "/vzekc-verlosung/merch-packets/999999/ship.json"
        expect(response.status).to eq(404)
      end
    end
  end
end
