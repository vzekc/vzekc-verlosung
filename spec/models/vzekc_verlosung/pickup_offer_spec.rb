# frozen_string_literal: true

RSpec.describe VzekcVerlosung::PickupOffer do
  describe ".collected_count" do
    fab!(:user)

    it "counts only picked_up offers for the user" do
      Fabricate(:pickup_offer, user: user, state: "picked_up")
      Fabricate(:pickup_offer, user: user, state: "picked_up")
      Fabricate(:pickup_offer, user: user, state: "assigned")
      Fabricate(:pickup_offer, user: user, state: "pending")

      expect(described_class.collected_count(user.id)).to eq(2)
    end

    it "is zero for a user without any pickups" do
      expect(described_class.collected_count(user.id)).to eq(0)
    end
  end
end
