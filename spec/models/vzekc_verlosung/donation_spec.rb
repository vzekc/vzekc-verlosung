# frozen_string_literal: true

RSpec.describe VzekcVerlosung::Donation do
  fab!(:facilitator, :user)

  # Give a user a history of +n+ collected (picked up) donations.
  def collected!(user, count)
    count.times do
      other = Fabricate(:donation, creator_user_id: facilitator.id)
      Fabricate(:pickup_offer, donation: other, user: user, state: "picked_up")
    end
  end

  describe "#auto_assign_selection" do
    fab!(:donation) { Fabricate(:donation, creator_user_id: facilitator.id, state: "open") }

    it "returns nil when there are no pending offers" do
      expect(donation.auto_assign_selection).to be_nil
    end

    it "selects the picker with the fewest collected donations" do
      low = Fabricate(:user)
      high = Fabricate(:user)
      collected!(low, 1)
      collected!(high, 3)
      Fabricate(:pickup_offer, donation: donation, user: low)
      Fabricate(:pickup_offer, donation: donation, user: high)

      selection = donation.auto_assign_selection

      expect(selection[:method]).to eq("least_collected")
      expect(selection[:offer].user_id).to eq(low.id)
      expect(selection[:min_count]).to eq(1)
    end

    it "breaks ties randomly between the lowest-count pickers" do
      pickers = Array.new(3) { Fabricate(:user) }
      pickers.each { |picker| collected!(picker, 2) }
      pickers.each { |picker| Fabricate(:pickup_offer, donation: donation, user: picker) }

      selection = donation.auto_assign_selection

      expect(selection[:method]).to eq("random")
      expect(selection[:tied_offers].size).to eq(3)
      expect(selection[:min_count]).to eq(2)
      expect(pickers.map(&:id)).to include(selection[:offer].user_id)
    end

    it "returns the same tie-break pick on repeated calls (stable seed)" do
      pickers = Array.new(3) { Fabricate(:user) }
      pickers.each { |picker| Fabricate(:pickup_offer, donation: donation, user: picker) }

      first = donation.auto_assign_selection[:offer].user_id
      expect(donation.auto_assign_selection[:offer].user_id).to eq(first)
    end
  end

  describe "#assignment_diverges?" do
    fab!(:donation) { Fabricate(:donation, creator_user_id: facilitator.id, state: "open") }

    it "is false with a single pending offer" do
      offer = Fabricate(:pickup_offer, donation: donation, user: Fabricate(:user))
      expect(donation.assignment_diverges?(offer)).to be false
    end

    it "is false when the chosen picker has the fewest collections" do
      low = Fabricate(:user)
      high = Fabricate(:user)
      collected!(high, 2)
      low_offer = Fabricate(:pickup_offer, donation: donation, user: low)
      Fabricate(:pickup_offer, donation: donation, user: high)

      expect(donation.assignment_diverges?(low_offer)).to be false
    end

    it "is true when the chosen picker has collected more than the lowest offerer" do
      low = Fabricate(:user)
      high = Fabricate(:user)
      collected!(high, 2)
      Fabricate(:pickup_offer, donation: donation, user: low)
      high_offer = Fabricate(:pickup_offer, donation: donation, user: high)

      expect(donation.assignment_diverges?(high_offer)).to be true
    end
  end

  describe "#assign_to!" do
    fab!(:topic)
    fab!(:donation) do
      Fabricate(:donation, creator_user_id: facilitator.id, state: "open", topic_id: topic.id)
    end

    def assign_random!(picker_count, collected_each: 0)
      pickers = Array.new(picker_count) { Fabricate(:user) }
      pickers.each do |picker|
        collected!(picker, collected_each)
        Fabricate(:pickup_offer, donation: donation, user: picker)
      end
      selection = donation.auto_assign_selection

      I18n.with_locale(:de) do
        donation.assign_to!(
          selection[:offer],
          contact_info: "Kontakt",
          actor: facilitator,
          method: selection[:method],
          tied_offers: selection[:tied_offers],
          collected_count: selection[:min_count],
        )
      end

      { pickers: pickers, raw: topic.posts.order(:post_number).last.raw }
    end

    it "posts a German response for a two-way tie using 'die beide'" do
      result = assign_random!(2)

      expect(result[:raw]).to include("zufällig")
      expect(result[:raw]).to include("die beide bisher noch keine Spende abgeholt haben")
      a, b = result[:pickers].map { |picker| "@#{picker.username}" }
      expect(result[:raw]).to match(/zwischen (#{a} und #{b}|#{b} und #{a}),/)
    end

    it "posts a German response for a three-way tie using 'die alle'" do
      result = assign_random!(3)

      expect(result[:raw]).to include("die alle bisher noch keine Spende abgeholt haben")
      result[:pickers].each { |picker| expect(result[:raw]).to include("@#{picker.username}") }
      expect(result[:raw]).to match(/, @\S+ und @\S+,/)
    end

    it "pluralizes the collected count when the tied pickers have a history" do
      result = assign_random!(2, collected_each: 1)

      expect(result[:raw]).to include("die beide bisher 1 Spende abgeholt haben")
    end
  end
end
