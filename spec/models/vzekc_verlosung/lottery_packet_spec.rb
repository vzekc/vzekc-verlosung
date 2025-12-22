# frozen_string_literal: true

RSpec.describe VzekcVerlosung::LotteryPacket do
  fab!(:user)
  fab!(:category)

  describe "associations" do
    it { is_expected.to belong_to(:lottery) }
    it { is_expected.to belong_to(:post).optional }
    it { is_expected.to have_many(:lottery_packet_winners).dependent(:destroy) }
    it { is_expected.to have_many(:lottery_tickets) }
  end

  describe "validations" do
    subject(:packet) { Fabricate(:lottery_packet) }

    it { is_expected.to validate_presence_of(:lottery_id) }
    it { is_expected.to validate_presence_of(:post_id) }
    it { is_expected.to validate_uniqueness_of(:post_id) }
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_numericality_of(:quantity).only_integer.is_greater_than(0) }
  end

  describe "scopes" do
    let!(:lottery) { Fabricate(:lottery) }
    let!(:winner_user) { Fabricate(:user) }

    let!(:packet_with_winner) do
      post = Fabricate(:post, topic: lottery.topic)
      packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
      packet.mark_winner!(winner_user)
      packet
    end

    let!(:packet_without_winner) do
      post = Fabricate(:post, topic: lottery.topic)
      Fabricate(:lottery_packet, lottery: lottery, post: post)
    end

    let!(:collected_packet) do
      post = Fabricate(:post, topic: lottery.topic)
      packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
      winner_entry = packet.mark_winner!(winner_user)
      winner_entry.mark_collected!
      packet
    end

    let!(:packet_with_report) do
      post = Fabricate(:post, topic: lottery.topic)
      report_topic = Fabricate(:topic)
      packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
      winner_entry = packet.mark_winner!(winner_user)
      winner_entry.mark_collected!
      winner_entry.link_report!(report_topic)
      packet
    end

    describe ".with_winner" do
      it "returns packets with winners assigned" do
        expect(described_class.with_winner).to contain_exactly(
          packet_with_winner,
          collected_packet,
          packet_with_report,
        )
      end
    end

    describe ".without_winner" do
      it "returns packets without winners" do
        expect(described_class.without_winner).to contain_exactly(packet_without_winner)
      end
    end

    describe ".requiring_report" do
      let!(:packet_not_requiring_report) do
        post = Fabricate(:post, topic: lottery.topic)
        Fabricate(:lottery_packet, lottery: lottery, post: post, erhaltungsbericht_required: false)
      end

      it "returns packets where erhaltungsbericht is required" do
        expect(described_class.requiring_report).to include(
          packet_with_winner,
          packet_without_winner,
          collected_packet,
          packet_with_report,
        )
        expect(described_class.requiring_report).not_to include(packet_not_requiring_report)
      end
    end
  end

  describe "helper methods" do
    describe "#has_winner?" do
      it "returns true when winner is assigned" do
        packet = Fabricate(:lottery_packet)
        packet.mark_winner!(Fabricate(:user))
        expect(packet.has_winner?).to be true
      end

      it "returns false when no winner" do
        packet = Fabricate(:lottery_packet)
        expect(packet.has_winner?).to be false
      end
    end

    describe "#all_instances_won?" do
      it "returns true when all instances have winners" do
        packet = Fabricate(:lottery_packet, quantity: 2)
        packet.mark_winner!(Fabricate(:user), instance_number: 1)
        packet.mark_winner!(Fabricate(:user), instance_number: 2)
        expect(packet.all_instances_won?).to be true
      end

      it "returns false when not all instances have winners" do
        packet = Fabricate(:lottery_packet, quantity: 2)
        packet.mark_winner!(Fabricate(:user), instance_number: 1)
        expect(packet.all_instances_won?).to be false
      end
    end

    describe "#remaining_instances" do
      it "returns count of instances without winners" do
        packet = Fabricate(:lottery_packet, quantity: 3)
        packet.mark_winner!(Fabricate(:user), instance_number: 1)
        expect(packet.remaining_instances).to eq(2)
      end
    end
  end

  describe "action methods" do
    describe "#mark_winner!" do
      it "creates a winner entry with timestamp" do
        packet = Fabricate(:lottery_packet)
        winner = Fabricate(:user)

        winner_entry = packet.mark_winner!(winner)

        expect(winner_entry).to be_persisted
        expect(winner_entry.winner_user_id).to eq(winner.id)
        expect(winner_entry.won_at).to be_within(1.second).of(Time.zone.now)
      end

      it "allows custom timestamp" do
        packet = Fabricate(:lottery_packet)
        winner = Fabricate(:user)
        custom_time = 2.days.ago

        winner_entry = packet.mark_winner!(winner, custom_time)

        expect(winner_entry.won_at).to be_within(1.second).of(custom_time)
      end

      it "auto-increments instance_number" do
        packet = Fabricate(:lottery_packet, quantity: 3)
        user1 = Fabricate(:user)
        user2 = Fabricate(:user)

        entry1 = packet.mark_winner!(user1)
        entry2 = packet.mark_winner!(user2)

        expect(entry1.instance_number).to eq(1)
        expect(entry2.instance_number).to eq(2)
      end

      it "allows explicit instance_number" do
        packet = Fabricate(:lottery_packet, quantity: 3)
        winner = Fabricate(:user)

        winner_entry = packet.mark_winner!(winner, instance_number: 2)

        expect(winner_entry.instance_number).to eq(2)
      end
    end

    describe "#mark_winners!" do
      it "creates multiple winner entries" do
        packet = Fabricate(:lottery_packet, quantity: 3)
        users = 3.times.map { Fabricate(:user) }

        packet.mark_winners!(users)

        expect(packet.lottery_packet_winners.count).to eq(3)
        expect(packet.winners).to match_array(users)
      end
    end
  end

  describe "deletion behavior" do
    context "when post is soft deleted" do
      it "does NOT delete the packet record" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)

        PostDestroyer.new(lottery.topic.user, post).destroy

        expect(described_class.find_by(id: packet.id)).to be_present
      end
    end

    context "when lottery is deleted" do
      it "CASCADE deletes all packets and winner entries" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        winner_entry = packet.mark_winner!(Fabricate(:user))
        winner_entry_id = winner_entry.id

        lottery.destroy!

        expect(described_class.find_by(id: packet.id)).to be_nil
        expect(VzekcVerlosung::LotteryPacketWinner.find_by(id: winner_entry_id)).to be_nil
      end
    end

    context "when winner user is deleted" do
      it "CASCADE deletes the winner entry" do
        packet = Fabricate(:lottery_packet)
        winner = Fabricate(:user)
        winner_entry = packet.mark_winner!(winner)
        winner_entry_id = winner_entry.id

        winner.destroy!

        expect(VzekcVerlosung::LotteryPacketWinner.find_by(id: winner_entry_id)).to be_nil
      end
    end

    context "when cascading to lottery tickets" do
      it "deletes associated tickets when lottery is deleted" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        user1 = Fabricate(:user)
        user2 = Fabricate(:user)

        ticket1 = Fabricate(:lottery_ticket, post: post, user: user1)
        ticket2 = Fabricate(:lottery_ticket, post: post, user: user2)

        lottery.destroy!

        expect(VzekcVerlosung::LotteryTicket.find_by(id: ticket1.id)).to be_nil
        expect(VzekcVerlosung::LotteryTicket.find_by(id: ticket2.id)).to be_nil
      end
    end
  end

  describe "#participants" do
    it "returns users who bought tickets for this packet" do
      packet = Fabricate(:lottery_packet)
      user1 = Fabricate(:user)
      user2 = Fabricate(:user)
      user3 = Fabricate(:user)

      Fabricate(:lottery_ticket, post: packet.post, user: user1)
      Fabricate(:lottery_ticket, post: packet.post, user: user2)

      other_post = Fabricate(:post)
      Fabricate(:lottery_ticket, post: other_post, user: user3)

      expect(packet.participants).to contain_exactly(user1, user2)
    end
  end

  describe "#participant_count" do
    it "returns count of tickets for this packet" do
      packet = Fabricate(:lottery_packet)
      user1 = Fabricate(:user)
      user2 = Fabricate(:user)

      Fabricate(:lottery_ticket, post: packet.post, user: user1)
      Fabricate(:lottery_ticket, post: packet.post, user: user2)

      expect(packet.participant_count).to eq(2)
    end
  end
end
