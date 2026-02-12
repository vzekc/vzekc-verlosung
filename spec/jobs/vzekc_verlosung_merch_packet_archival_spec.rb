# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungMerchPacketArchival do
  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#execute" do
    context "when plugin is disabled" do
      before { SiteSetting.vzekc_verlosung_enabled = false }

      it "does nothing" do
        old_packet =
          Fabricate(
            :merch_packet,
            donation: Fabricate(:donation),
            state: "shipped",
            shipped_at: 5.weeks.ago,
          )

        described_class.new.execute({})

        old_packet.reload
        expect(old_packet.state).to eq("shipped")
      end
    end

    context "with shipped packets" do
      let!(:old_packet) do
        Fabricate(
          :merch_packet,
          donation: Fabricate(:donation),
          state: "shipped",
          shipped_at: 5.weeks.ago,
        )
      end
      let!(:recent_packet) do
        Fabricate(
          :merch_packet,
          donation: Fabricate(:donation),
          state: "shipped",
          shipped_at: 2.weeks.ago,
        )
      end
      let!(:pending_packet) do
        Fabricate(:merch_packet, donation: Fabricate(:donation), state: "pending")
      end

      it "archives packets shipped more than 4 weeks ago" do
        described_class.new.execute({})

        old_packet.reload
        expect(old_packet.state).to eq("archived")
        expect(old_packet.donor_name).to be_nil
      end

      it "does not archive recently shipped packets" do
        described_class.new.execute({})

        recent_packet.reload
        expect(recent_packet.state).to eq("shipped")
        expect(recent_packet.donor_name).to be_present
      end

      it "does not archive pending packets" do
        described_class.new.execute({})

        pending_packet.reload
        expect(pending_packet.state).to eq("pending")
      end
    end
  end
end
