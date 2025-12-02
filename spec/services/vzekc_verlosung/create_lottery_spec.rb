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
        raw: "Beschreibung der Verlosung",
        duration_days: 14,
        category_id: category.id,
        packet_mode: "mehrere",
        packets: [
          {
            "title" => "Abholerpaket",
            "raw" => "Inhalt Abholerpaket",
            "ordinal" => 0,
            "is_abholerpaket" => true,
          },
          { "title" => "Packet 1", "raw" => "Inhalt 1", "ordinal" => 1 },
          { "title" => "Packet 2", "raw" => "Inhalt 2", "ordinal" => 2 },
        ],
      },
    }
  end

  let(:single_packet_params) do
    {
      user: user,
      guardian: Guardian.new(user),
      params: {
        title: "Einzelnes Hardware Paket",
        raw: "Beschreibung des einzelnen Pakets",
        duration_days: 14,
        category_id: category.id,
        packet_mode: "ein",
        single_packet_erhaltungsbericht_required: true,
        packets: [],
      },
    }
  end

  describe "#call" do
    context "with mehrere pakete mode" do
      it "creates main topic and packet posts" do
        expect { described_class.call(**valid_params) }.to change { Topic.count }.by(1).and change {
                Post.count
              }.by(4) # intro post + Abholerpaket + 2 user packets
      end

      it "returns success with main topic" do
        result = described_class.call(**valid_params)

        expect(result).to be_success
        expect(result.main_topic).to be_a(Topic)
        expect(result.main_topic.title).to eq("Hardware Verlosung Januar 2025")
      end

      it "creates lottery in active state" do
        result = described_class.call(**valid_params)

        lottery = VzekcVerlosung::Lottery.find_by(topic_id: result.main_topic.id)
        expect(lottery.state).to eq("active")
      end

      it "creates lottery with mehrere packet mode" do
        result = described_class.call(**valid_params)

        lottery = VzekcVerlosung::Lottery.find_by(topic_id: result.main_topic.id)
        expect(lottery.packet_mode).to eq("mehrere")
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
        expect(packet_posts.count).to eq(3) # Abholerpaket + 2 user packets
        expect(packet_posts.map(&:raw)).to include(
          match(/Paket 0/),
          match(/Paket 1/),
          match(/Paket 2/),
        )
      end

      it "assigns Abholerpaket to creator and marks as collected" do
        result = described_class.call(**valid_params)

        abholerpaket =
          VzekcVerlosung::LotteryPacket.find_by(lottery_id: result.lottery.id, abholerpaket: true)
        expect(abholerpaket).to be_present
        expect(abholerpaket.winner_user_id).to eq(user.id)
        expect(abholerpaket.won_at).to be_present
        expect(abholerpaket.collected_at).to be_present
      end

      it "stores correct ordinals for packets" do
        result = described_class.call(**valid_params)

        lottery_packets =
          VzekcVerlosung::LotteryPacket.where(lottery_id: result.lottery.id).order(:ordinal)
        expect(lottery_packets.pluck(:ordinal)).to eq([0, 1, 2])
      end
    end

    context "with ein paket mode" do
      it "creates main topic without additional packet posts" do
        expect { described_class.call(**single_packet_params) }.to change { Topic.count }.by(
          1,
        ).and change { Post.count }.by(1) # only intro post
      end

      it "returns success with main topic" do
        result = described_class.call(**single_packet_params)

        expect(result).to be_success
        expect(result.main_topic).to be_a(Topic)
        expect(result.main_topic.title).to eq("Einzelnes Hardware Paket")
      end

      it "creates lottery with ein packet mode" do
        result = described_class.call(**single_packet_params)

        lottery = VzekcVerlosung::Lottery.find_by(topic_id: result.main_topic.id)
        expect(lottery.packet_mode).to eq("ein")
      end

      it "creates one LotteryPacket pointing to the main post" do
        result = described_class.call(**single_packet_params)

        lottery_packets = VzekcVerlosung::LotteryPacket.where(lottery_id: result.lottery.id)
        expect(lottery_packets.count).to eq(1)

        packet = lottery_packets.first
        expect(packet.post_id).to eq(result.main_topic.posts.first.id)
        expect(packet.ordinal).to eq(1)
        expect(packet.abholerpaket).to be false
      end

      it "uses lottery title as packet title" do
        result = described_class.call(**single_packet_params)

        packet = VzekcVerlosung::LotteryPacket.find_by(lottery_id: result.lottery.id)
        expect(packet.title).to eq("Einzelnes Hardware Paket")
      end

      it "respects single_packet_erhaltungsbericht_required setting" do
        result = described_class.call(**single_packet_params)

        packet = VzekcVerlosung::LotteryPacket.find_by(lottery_id: result.lottery.id)
        expect(packet.erhaltungsbericht_required).to be true
      end

      it "allows disabling erhaltungsbericht requirement" do
        params_without_report =
          single_packet_params.merge(
            params:
              single_packet_params[:params].merge(single_packet_erhaltungsbericht_required: false),
          )
        result = described_class.call(**params_without_report)

        packet = VzekcVerlosung::LotteryPacket.find_by(lottery_id: result.lottery.id)
        expect(packet.erhaltungsbericht_required).to be false
      end

      it "allows empty packets array" do
        result = described_class.call(**single_packet_params)
        expect(result).to be_success
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

      it "fails when raw is missing" do
        invalid_params = valid_params.merge(params: valid_params[:params].merge(raw: ""))
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "fails when packets array is empty in mehrere mode" do
        invalid_params =
          valid_params.merge(
            params: valid_params[:params].merge(packet_mode: "mehrere", packets: []),
          )
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "succeeds when packets array is empty in ein mode" do
        valid_ein_params =
          valid_params.merge(params: valid_params[:params].merge(packet_mode: "ein", packets: []))
        result = described_class.call(**valid_ein_params)

        expect(result).to be_success
      end

      it "fails when category does not exist" do
        invalid_params =
          valid_params.merge(params: valid_params[:params].merge(category_id: 99_999))
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end

      it "fails when packet_mode is invalid" do
        invalid_params =
          valid_params.merge(params: valid_params[:params].merge(packet_mode: "invalid"))
        result = described_class.call(**invalid_params)

        expect(result).to be_failure
      end
    end
  end
end
