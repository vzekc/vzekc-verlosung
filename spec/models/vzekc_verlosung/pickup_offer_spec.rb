# frozen_string_literal: true

RSpec.describe VzekcVerlosung::PickupOffer do
  describe ".pickup_stats" do
    fab!(:user)

    def picked_up!(donation_attrs = {}, picked_up_at: 1.month.ago)
      donation = Fabricate(:donation, donation_attrs.merge(state: "closed"))
      Fabricate(
        :pickup_offer,
        donation: donation,
        user: user,
        state: "picked_up",
        picked_up_at: picked_up_at,
      )
      donation
    end

    def stats
      described_class.pickup_stats_for(user.id)
    end

    it "is zero for a user without any pickups" do
      expect(stats).to eq(kept: 0, pending: 0, partial: 0, passed_on: 0, balance: 0)
    end

    it "counts a donation with an Erhaltungsbericht as kept" do
      picked_up!({ erhaltungsbericht_topic_id: Fabricate(:topic).id })

      expect(stats).to include(kept: 1, balance: 1)
    end

    it "counts a picked-up donation without outcome as pending" do
      picked_up!

      expect(stats).to include(pending: 1, balance: 1)
    end

    it "counts a raffled donation as passed on" do
      donation = picked_up!
      Fabricate(:lottery, donation: donation)

      expect(stats).to include(passed_on: 1, balance: -1)
    end

    it "counts a lottery with an Abholerpaket as partial" do
      donation = picked_up!
      lottery = Fabricate(:lottery, donation: donation)
      Fabricate(
        :lottery_packet,
        lottery: lottery,
        abholerpaket: true,
        post: Fabricate(:post, topic: lottery.topic),
      )

      expect(stats).to include(partial: 1, balance: 0)
    end

    it "ignores offers that were not picked up" do
      Fabricate(:pickup_offer, user: user, state: "assigned")
      Fabricate(:pickup_offer, user: user, state: "pending")

      expect(stats[:balance]).to eq(0)
    end

    it "ignores pickups older than 24 months" do
      picked_up!({ erhaltungsbericht_topic_id: Fabricate(:topic).id }, picked_up_at: 25.months.ago)

      expect(stats[:kept]).to eq(0)
    end
  end
end
