# frozen_string_literal: true

RSpec.describe VzekcVerlosung::MerchPacket do
  fab!(:user)
  fab!(:donation)

  describe "associations" do
    it { is_expected.to belong_to(:donation).class_name("VzekcVerlosung::Donation") }
    it { is_expected.to belong_to(:shipped_by_user).class_name("User").optional }
  end

  describe "validations" do
    subject(:merch_packet) { Fabricate.build(:merch_packet, donation: donation) }

    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_inclusion_of(:state).in_array(%w[pending shipped archived]) }

    context "when not archived" do
      it "requires donor_name" do
        merch_packet.donor_name = nil
        expect(merch_packet).not_to be_valid
        expect(merch_packet.errors[:donor_name]).to be_present
      end

      it "requires donor_street" do
        merch_packet.donor_street = nil
        expect(merch_packet).not_to be_valid
        expect(merch_packet.errors[:donor_street]).to be_present
      end

      it "requires donor_street_number" do
        merch_packet.donor_street_number = nil
        expect(merch_packet).not_to be_valid
        expect(merch_packet.errors[:donor_street_number]).to be_present
      end

      it "requires donor_postcode" do
        merch_packet.donor_postcode = nil
        expect(merch_packet).not_to be_valid
        expect(merch_packet.errors[:donor_postcode]).to be_present
      end

      it "requires donor_city" do
        merch_packet.donor_city = nil
        expect(merch_packet).not_to be_valid
        expect(merch_packet.errors[:donor_city]).to be_present
      end
    end

    context "when archived" do
      it "allows nil address fields" do
        merch_packet.state = "archived"
        merch_packet.donor_name = nil
        merch_packet.donor_street = nil
        merch_packet.donor_street_number = nil
        merch_packet.donor_postcode = nil
        merch_packet.donor_city = nil
        expect(merch_packet).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:pending_packet) do
      Fabricate(:merch_packet, donation: Fabricate(:donation), state: "pending")
    end
    let!(:shipped_packet) do
      Fabricate(
        :merch_packet,
        donation: Fabricate(:donation),
        state: "shipped",
        shipped_at: Time.zone.now,
      )
    end
    let!(:archived_packet) do
      Fabricate(
        :merch_packet,
        donation: Fabricate(:donation),
        state: "archived",
        donor_name: nil,
        donor_street: nil,
        donor_street_number: nil,
        donor_postcode: nil,
        donor_city: nil,
      )
    end

    describe ".pending" do
      it "returns only pending packets" do
        expect(described_class.pending).to contain_exactly(pending_packet)
      end
    end

    describe ".shipped" do
      it "returns only shipped packets" do
        expect(described_class.shipped).to contain_exactly(shipped_packet)
      end
    end

    describe ".archived" do
      it "returns only archived packets" do
        expect(described_class.archived).to contain_exactly(archived_packet)
      end
    end

    describe ".needs_archival" do
      let!(:old_shipped_packet) do
        Fabricate(
          :merch_packet,
          donation: Fabricate(:donation),
          state: "shipped",
          shipped_at: 5.weeks.ago,
        )
      end

      it "returns shipped packets older than 4 weeks" do
        expect(described_class.needs_archival).to contain_exactly(old_shipped_packet)
      end

      it "excludes recently shipped packets" do
        expect(described_class.needs_archival).not_to include(shipped_packet)
      end
    end
  end

  describe "state helpers" do
    it "#pending? returns true for pending state" do
      packet = Fabricate(:merch_packet, donation: donation, state: "pending")
      expect(packet.pending?).to be true
      expect(packet.shipped?).to be false
      expect(packet.archived?).to be false
    end

    it "#shipped? returns true for shipped state" do
      packet =
        Fabricate(:merch_packet, donation: donation, state: "shipped", shipped_at: Time.zone.now)
      expect(packet.pending?).to be false
      expect(packet.shipped?).to be true
      expect(packet.archived?).to be false
    end

    it "#archived? returns true for archived state" do
      packet =
        Fabricate(
          :merch_packet,
          donation: donation,
          state: "archived",
          donor_name: nil,
          donor_street: nil,
          donor_street_number: nil,
          donor_postcode: nil,
          donor_city: nil,
        )
      expect(packet.pending?).to be false
      expect(packet.shipped?).to be false
      expect(packet.archived?).to be true
    end
  end

  describe "#mark_shipped!" do
    let(:merch_packet) { Fabricate(:merch_packet, donation: donation) }

    it "updates state to shipped" do
      merch_packet.mark_shipped!(user)
      expect(merch_packet.state).to eq("shipped")
    end

    it "sets shipped_at timestamp" do
      freeze_time do
        merch_packet.mark_shipped!(user)
        expect(merch_packet.shipped_at).to eq_time(Time.zone.now)
      end
    end

    it "sets shipped_by_user" do
      merch_packet.mark_shipped!(user)
      expect(merch_packet.shipped_by_user).to eq(user)
    end

    it "stores tracking info if provided" do
      merch_packet.mark_shipped!(user, tracking_info: "DHL 123456")
      expect(merch_packet.tracking_info).to eq("DHL 123456")
    end
  end

  describe "#archive!" do
    let(:merch_packet) do
      Fabricate(:merch_packet, donation: donation, state: "shipped", shipped_at: 5.weeks.ago)
    end

    it "sets state to archived" do
      merch_packet.archive!
      expect(merch_packet.state).to eq("archived")
    end

    it "clears personal data" do
      merch_packet.archive!
      expect(merch_packet.donor_name).to be_nil
      expect(merch_packet.donor_company).to be_nil
      expect(merch_packet.donor_street).to be_nil
      expect(merch_packet.donor_street_number).to be_nil
      expect(merch_packet.donor_postcode).to be_nil
      expect(merch_packet.donor_city).to be_nil
      expect(merch_packet.donor_email).to be_nil
    end
  end

  describe "#formatted_address" do
    it "returns formatted address" do
      packet =
        Fabricate(
          :merch_packet,
          donation: donation,
          donor_name: "John Doe",
          donor_company: "ACME Inc",
          donor_street: "Main Street",
          donor_street_number: "123",
          donor_postcode: "12345",
          donor_city: "Berlin",
        )
      expected = "John Doe\nACME Inc\nMain Street 123\n12345 Berlin"
      expect(packet.formatted_address).to eq(expected)
    end

    it "omits company if not present" do
      packet = Fabricate(:merch_packet, donation: donation, donor_company: nil)
      expect(packet.formatted_address).not_to include("\n\n")
    end

    it "returns empty string when archived" do
      packet =
        Fabricate(
          :merch_packet,
          donation: donation,
          state: "archived",
          donor_name: nil,
          donor_street: nil,
          donor_street_number: nil,
          donor_postcode: nil,
          donor_city: nil,
        )
      expect(packet.formatted_address).to eq("")
    end
  end
end
