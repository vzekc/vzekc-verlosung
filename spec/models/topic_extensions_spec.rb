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

  describe "#erhaltungsbericht_source_packet" do
    fab!(:lottery_topic) { Fabricate(:topic, category: category, user: user) }
    fab!(:lottery) do
      VzekcVerlosung::Lottery.create!(
        topic_id: lottery_topic.id,
        state: "finished",
        duration_days: 14,
      )
    end
    fab!(:packet_post) { Fabricate(:post, topic: lottery_topic, user: user) }
    fab!(:packet) do
      VzekcVerlosung::LotteryPacket.create!(
        lottery_id: lottery.id,
        post_id: packet_post.id,
        ordinal: 1,
        title: "Amiga 2000",
      )
    end
    fab!(:report) { Fabricate(:topic, category: other_category) }
    let(:guardian) { Guardian.new(report.user) }

    before do
      SiteSetting.vzekc_verlosung_enabled = true
      SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id = other_category.id.to_s
    end

    it "links the report to the packet and lottery of the win it reports on" do
      VzekcVerlosung::LotteryPacketWinner.create!(
        lottery_packet: packet,
        winner_user_id: report.user_id,
        instance_number: 1,
        fulfillment_state: "completed",
        erhaltungsbericht_topic_id: report.id,
      )

      expect(Topic.find(report.id).erhaltungsbericht_source_packet(guardian)).to eq(
        lottery_title: lottery_topic.title,
        lottery_url: lottery_topic.relative_url,
        packet_title: "Amiga 2000",
        packet_url: "#{lottery_topic.relative_url}/#{packet_post.post_number}",
      )
    end

    it "is nil for a topic that is no report" do
      expect(report.erhaltungsbericht_source_packet(guardian)).to be_nil
    end

    it "is nil for viewers who cannot see the lottery" do
      VzekcVerlosung::LotteryPacketWinner.create!(
        lottery_packet: packet,
        winner_user_id: report.user_id,
        instance_number: 1,
        fulfillment_state: "completed",
        erhaltungsbericht_topic_id: report.id,
      )
      category.set_permissions(staff: :full)
      category.save!

      expect(Topic.find(report.id).erhaltungsbericht_source_packet(guardian)).to be_nil
    end
  end
end
