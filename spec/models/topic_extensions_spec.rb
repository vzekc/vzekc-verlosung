# frozen_string_literal: true

RSpec.describe Topic do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:category)
  fab!(:other_category, :category)

  describe "lottery category change validation" do
    let!(:topic) { Fabricate(:topic, category: category, user: user) }
    let!(:lottery) do
      VzekcVerlosung::Lottery.create!(
        topic_id: topic.id,
        state: "active",
        duration_days: 14,
        drawing_mode: "automatic",
        packet_mode: "mehrere",
        ends_at: 14.days.from_now,
      )
    end

    it "prevents changing category of a lottery topic" do
      topic.category_id = other_category.id
      expect(topic).not_to be_valid
      expect(topic.errors[:category_id]).to include(
        I18n.t("vzekc_verlosung.errors.cannot_change_lottery_category"),
      )
    end

    it "allows saving lottery topic without category change" do
      topic.title = "Updated Title That Is Long Enough"
      expect(topic).to be_valid
    end

    context "when topic is not a lottery" do
      let!(:regular_topic) { Fabricate(:topic, category: category, user: user) }

      it "allows changing category" do
        regular_topic.category_id = other_category.id
        expect(regular_topic).to be_valid
      end
    end
  end
end
