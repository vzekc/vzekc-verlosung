# frozen_string_literal: true

RSpec.describe VzekcVerlosung::GuardianExtensions do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:other_user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:admin)
  fab!(:category)

  let(:lottery_result) do
    VzekcVerlosung::CreateLottery.call(
      params: {
        title: "Test Lottery",
        raw: "Test lottery content",
        duration_days: 14,
        category_id: category.id,
        packets: [{ title: "Packet 1", raw: "Content" }],
      },
      user: user,
      guardian: Guardian.new(user),
    )
  end
  let(:lottery_topic) { lottery_result.main_topic }
  let!(:regular_topic) do
    topic = Fabricate(:topic, user: user, category: category)
    topic
  end

  # Force lottery creation before tests
  before { lottery_topic }

  describe "setup" do
    it "creates an active lottery" do
      expect(lottery_result).to be_success
      lottery = VzekcVerlosung::Lottery.find_by(topic_id: lottery_topic.id)
      expect(lottery).to be_present
      expect(lottery.state).to eq("active")
    end
  end

  describe "#can_create_post_in_lottery_draft?" do
    context "when topic is not a lottery" do
      it "allows any user to post" do
        guardian = Guardian.new(other_user)
        expect(guardian.can_create_post_in_lottery_draft?(regular_topic)).to eq(true)
      end
    end

    context "when topic is an active lottery" do
      it "allows the owner to post" do
        guardian = Guardian.new(user)
        expect(guardian.can_create_post_in_lottery_draft?(lottery_topic)).to eq(true)
      end

      it "allows staff to post" do
        guardian = Guardian.new(admin)
        expect(guardian.can_create_post_in_lottery_draft?(lottery_topic)).to eq(true)
      end

      it "allows other users to post" do
        guardian = Guardian.new(other_user)
        expect(guardian.can_create_post_in_lottery_draft?(lottery_topic)).to eq(true)
      end
    end
  end

  describe "#can_create_post?" do
    context "when topic is an active lottery" do
      it "allows other users to create posts" do
        guardian = Guardian.new(other_user)
        expect(guardian.can_create_post?(lottery_topic)).to eq(true)
      end

      it "allows owners to create posts" do
        guardian = Guardian.new(user)
        expect(guardian.can_create_post?(lottery_topic)).to eq(true)
      end

      it "allows staff to create posts" do
        guardian = Guardian.new(admin)
        expect(guardian.can_create_post?(lottery_topic)).to eq(true)
      end
    end
  end
end
