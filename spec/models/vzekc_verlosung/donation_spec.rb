# frozen_string_literal: true

RSpec.describe VzekcVerlosung::Donation do
  fab!(:facilitator, :user)

  # Give a user a history of +count+ picked-up donations without an outcome
  # yet, each adding +1 to the user's pickup balance.
  def collected!(user, count)
    count.times do
      other = Fabricate(:donation, creator_user_id: facilitator.id)
      Fabricate(:pickup_offer, donation: other, user: user, state: "picked_up")
    end
  end

  # Give a user a history of +count+ donations passed on through a lottery,
  # each subtracting 1 from the user's pickup balance.
  def passed_on!(user, count)
    count.times do
      other = Fabricate(:donation, creator_user_id: facilitator.id)
      Fabricate(:pickup_offer, donation: other, user: user, state: "picked_up")
      Fabricate(:lottery, donation: other)
    end
  end

  describe "#auto_assign_selection" do
    fab!(:donation) { Fabricate(:donation, creator_user_id: facilitator.id, state: "open") }

    it "returns nil when there are no pending offers" do
      expect(donation.auto_assign_selection).to be_nil
    end

    it "selects the picker with the lowest pickup balance" do
      low = Fabricate(:user)
      high = Fabricate(:user)
      collected!(low, 1)
      collected!(high, 3)
      Fabricate(:pickup_offer, donation: donation, user: low)
      Fabricate(:pickup_offer, donation: donation, user: high)

      selection = donation.auto_assign_selection

      expect(selection[:method]).to eq("lowest_balance")
      expect(selection[:offer].user_id).to eq(low.id)
      expect(selection[:min_balance]).to eq(1)
    end

    it "prefers a picker who passed donations on over one without pickups" do
      newcomer = Fabricate(:user)
      raffler = Fabricate(:user)
      passed_on!(raffler, 2)
      collected!(raffler, 1)
      Fabricate(:pickup_offer, donation: donation, user: newcomer)
      Fabricate(:pickup_offer, donation: donation, user: raffler)

      selection = donation.auto_assign_selection

      expect(selection[:offer].user_id).to eq(raffler.id)
      expect(selection[:min_balance]).to eq(-1)
    end

    it "breaks ties randomly between the lowest-balance pickers" do
      pickers = Array.new(3) { Fabricate(:user) }
      pickers.each { |picker| collected!(picker, 2) }
      pickers.each { |picker| Fabricate(:pickup_offer, donation: donation, user: picker) }

      selection = donation.auto_assign_selection

      expect(selection[:method]).to eq("random")
      expect(selection[:tied_offers].size).to eq(3)
      expect(selection[:min_balance]).to eq(2)
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

    it "is false when the chosen picker has the lowest balance" do
      low = Fabricate(:user)
      high = Fabricate(:user)
      collected!(high, 2)
      low_offer = Fabricate(:pickup_offer, donation: donation, user: low)
      Fabricate(:pickup_offer, donation: donation, user: high)

      expect(donation.assignment_diverges?(low_offer)).to be false
    end

    it "is true when the chosen picker has a higher balance than the lowest offerer" do
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
          balance: selection[:min_balance],
        )
      end

      { pickers: pickers, raw: topic.posts.order(:post_number).last.raw }
    end

    it "posts a German response for a two-way tie using 'die beide'" do
      result = assign_random!(2)

      expect(result[:raw]).to include("zufällig")
      expect(result[:raw]).to include("die beide den niedrigsten Abholsaldo haben (0)")
      a, b = result[:pickers].map { |picker| "@#{picker.username}" }
      expect(result[:raw]).to match(/zwischen (#{a} und #{b}|#{b} und #{a}),/)
    end

    it "posts a German response for a three-way tie using 'die alle'" do
      result = assign_random!(3)

      expect(result[:raw]).to include("die alle den niedrigsten Abholsaldo haben (0)")
      result[:pickers].each { |picker| expect(result[:raw]).to include("@#{picker.username}") }
      expect(result[:raw]).to match(/, @\S+ und @\S+,/)
    end

    it "shows the shared balance with its sign when the tied pickers have a history" do
      result = assign_random!(2, collected_each: 1)

      expect(result[:raw]).to include("niedrigsten Abholsaldo haben (+1)")
    end
  end

  describe "#close!" do
    it "records when the donation was closed" do
      donation = Fabricate(:donation, creator_user_id: facilitator.id, state: "open")

      freeze_time do
        donation.close!

        expect(donation.reload.closed_at).to eq_time(Time.zone.now)
      end
    end
  end
end
