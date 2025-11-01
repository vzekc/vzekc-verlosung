# frozen_string_literal: true

RSpec.describe VzekcVerlosung::GuardianExtensions do
  fab!(:user)
  fab!(:other_user) { Fabricate(:user) }
  fab!(:admin) { Fabricate(:admin) }
  fab!(:category)

  let(:lottery_result) do
    VzekcVerlosung::CreateLottery.call(
      params: {
        title: "Test Lottery",
        description: "Test description",
        category_id: category.id,
        packets: [{ title: "Packet 1", description: "Content" }],
      },
      user: user,
      guardian: Guardian.new(user),
    )
  end
  let(:draft_topic) { lottery_result.main_topic }
  let!(:published_topic) do
    topic = Fabricate(:topic, user: user, category: category)
    topic
  end

  describe "#can_create_post_in_lottery_draft?" do
    context "when topic is not a draft" do
      it "allows any user to post" do
        guardian = Guardian.new(other_user)
        expect(guardian.can_create_post_in_lottery_draft?(published_topic)).to eq(true)
      end
    end

    context "when topic is a draft" do
      it "allows the owner to post" do
        guardian = Guardian.new(user)
        expect(guardian.can_create_post_in_lottery_draft?(draft_topic)).to eq(true)
      end

      it "allows staff to post" do
        guardian = Guardian.new(admin)
        expect(guardian.can_create_post_in_lottery_draft?(draft_topic)).to eq(true)
      end

      it "prevents other users from posting" do
        guardian = Guardian.new(other_user)
        expect(guardian.can_create_post_in_lottery_draft?(draft_topic)).to eq(false)
      end

      it "prevents anonymous users from posting" do
        guardian = Guardian.new(nil)
        expect(guardian.can_create_post_in_lottery_draft?(draft_topic)).to eq(false)
      end
    end
  end

  describe "#can_create_post?" do
    context "when topic is a lottery draft" do
      it "prevents non-owners from creating posts" do
        guardian = Guardian.new(other_user)
        expect(guardian.can_create_post?(draft_topic)).to eq(false)
      end

      it "allows owners to create posts" do
        guardian = Guardian.new(user)
        expect(guardian.can_create_post?(draft_topic)).to eq(true)
      end

      it "allows staff to create posts" do
        guardian = Guardian.new(admin)
        expect(guardian.can_create_post?(draft_topic)).to eq(true)
      end
    end
  end
end
