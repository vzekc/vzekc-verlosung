# frozen_string_literal: true

RSpec.describe VzekcVerlosung::CreateLottery do
  fab!(:user) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:category)

  let(:valid_params) do
    {
      user: user,
      guardian: Guardian.new(user),
      params: {
        title: "Hardware Verlosung Januar 2025",
        duration_days: 14,
        category_id: category.id,
        packets: [
          { "title" => "Packet 1", "description" => "Inhalt 1" },
          { "title" => "Packet 2", "description" => "Inhalt 2" },
        ],
      },
    }
  end

  describe "#call" do
    context "when user can create topics" do
      it "creates main topic and packet posts" do
        expect { described_class.call(**valid_params) }.to change { Topic.count }.by(1).and change {
                Post.count
              }.by(3) # intro post + 2 user packets (Abholerpaket has no post)
      end

      it "returns success with main topic" do
        result = described_class.call(**valid_params)

        expect(result).to be_success
        expect(result.main_topic).to be_a(Topic)
        expect(result.main_topic.title).to eq("Hardware Verlosung Januar 2025")
      end

      it "marks the main topic as a draft" do
        result = described_class.call(**valid_params)

        lottery = VzekcVerlosung::Lottery.find_by(topic_id: result.main_topic.id)
        expect(lottery.state).to eq("draft")
      end

      it "creates lottery with automatic drawing mode by default" do
        result = described_class.call(**valid_params)

        lottery = VzekcVerlosung::Lottery.find_by(topic_id: result.main_topic.id)
        expect(lottery.drawing_mode).to eq("automatic")
      end

      it "creates lottery with manual drawing mode when specified" do
        manual_params =
          valid_params.merge(params: valid_params[:params].merge(drawing_mode: "manual"))
        result = described_class.call(**manual_params)

        lottery = VzekcVerlosung::Lottery.find_by(topic_id: result.main_topic.id)
        expect(lottery.drawing_mode).to eq("manual")
      end

      it "creates packet posts in the main topic" do
        result = described_class.call(**valid_params)

        lottery_packets = VzekcVerlosung::LotteryPacket.where(lottery_id: result.lottery.id)
        expect(lottery_packets.count).to eq(3) # abholerpaket + 2 user packets
        user_packets = lottery_packets.where(abholerpaket: false)
        expect(user_packets.pluck(:title)).to contain_exactly("Packet 1", "Packet 2")
      end

      it "creates posts with packet content" do
        result = described_class.call(**valid_params)

        packet_posts = result.main_topic.posts.where.not(post_number: 1)
        expect(packet_posts.count).to eq(2) # 2 user packets (Abholerpaket has no post)
        expect(packet_posts.map(&:raw)).to include(match(/Packet 1/), match(/Packet 2/))
      end
    end

    context "when user cannot create topics" do
      fab!(:readonly_category) { Fabricate(:private_category, group: Fabricate(:group)) }

      let(:params_with_readonly_category) do
        valid_params.merge(params: valid_params[:params].merge(category_id: readonly_category.id))
      end

      it "fails with policy error" do
        result = described_class.call(**params_with_readonly_category)

        expect(result).to be_failure
      end
    end

    context "with invalid params" do
      it "fails when title is missing" do
        invalid_params = valid_params.merge(params: valid_params[:params].merge(title: ""))
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "fails when packets array is empty" do
        invalid_params = valid_params.merge(params: valid_params[:params].merge(packets: []))
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "fails when category does not exist" do
        invalid_params =
          valid_params.merge(params: valid_params[:params].merge(category_id: 99_999))
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end
    end
  end
end
