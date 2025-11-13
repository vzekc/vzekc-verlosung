# frozen_string_literal: true

RSpec.describe VzekcVerlosung::LotteryPacket do
  fab!(:user)
  fab!(:category)

  describe "associations" do
    it { is_expected.to belong_to(:lottery) }
    it { is_expected.to belong_to(:post) }
    it { is_expected.to belong_to(:winner).optional }
    it { is_expected.to belong_to(:erhaltungsbericht_topic).optional }
    it { is_expected.to have_many(:lottery_tickets) }
  end

  describe "validations" do
    subject(:packet) { Fabricate(:lottery_packet) }

    it { is_expected.to validate_presence_of(:lottery_id) }
    it { is_expected.to validate_presence_of(:post_id) }
    it { is_expected.to validate_uniqueness_of(:post_id) }
    it { is_expected.to validate_presence_of(:title) }
  end

  describe "scopes" do
    let!(:lottery) { Fabricate(:lottery) }
    let!(:winner_user) { Fabricate(:user) }

    let!(:packet_with_winner) do
      post = Fabricate(:post, topic: lottery.topic)
      Fabricate(
        :lottery_packet,
        lottery: lottery,
        post: post,
        winner_user_id: winner_user.id,
        won_at: Time.zone.now,
      )
    end

    let!(:packet_without_winner) do
      post = Fabricate(:post, topic: lottery.topic)
      Fabricate(:lottery_packet, lottery: lottery, post: post, winner_user_id: nil)
    end

    let!(:collected_packet) do
      post = Fabricate(:post, topic: lottery.topic)
      Fabricate(
        :lottery_packet,
        lottery: lottery,
        post: post,
        winner_user_id: winner_user.id,
        won_at: Time.zone.now,
        collected_at: Time.zone.now,
      )
    end

    let!(:packet_with_report) do
      post = Fabricate(:post, topic: lottery.topic)
      report_topic = Fabricate(:topic)
      Fabricate(
        :lottery_packet,
        lottery: lottery,
        post: post,
        winner_user_id: winner_user.id,
        collected_at: Time.zone.now,
        erhaltungsbericht_topic_id: report_topic.id,
      )
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

    describe ".collected" do
      it "returns packets that have been collected" do
        expect(described_class.collected).to contain_exactly(collected_packet, packet_with_report)
      end
    end

    describe ".uncollected" do
      it "returns packets with winners but not collected" do
        expect(described_class.uncollected).to contain_exactly(packet_with_winner)
      end
    end

    describe ".with_report" do
      it "returns packets with erhaltungsbericht topics" do
        expect(described_class.with_report).to contain_exactly(packet_with_report)
      end
    end

    describe ".without_report" do
      it "returns packets without erhaltungsbericht topics" do
        expect(described_class.without_report).to contain_exactly(
          packet_with_winner,
          packet_without_winner,
          collected_packet,
        )
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
        packet = Fabricate(:lottery_packet, winner_user_id: Fabricate(:user).id)
        expect(packet.has_winner?).to be true
      end

      it "returns false when no winner" do
        packet = Fabricate(:lottery_packet, winner_user_id: nil)
        expect(packet.has_winner?).to be false
      end
    end

    describe "#collected?" do
      it "returns true when collected_at is set" do
        packet = Fabricate(:lottery_packet, collected_at: Time.zone.now)
        expect(packet.collected?).to be true
      end

      it "returns false when collected_at is nil" do
        packet = Fabricate(:lottery_packet, collected_at: nil)
        expect(packet.collected?).to be false
      end
    end

    describe "#has_report?" do
      it "returns true when erhaltungsbericht_topic_id is set" do
        topic = Fabricate(:topic)
        packet = Fabricate(:lottery_packet, erhaltungsbericht_topic_id: topic.id)
        expect(packet.has_report?).to be true
      end

      it "returns false when erhaltungsbericht_topic_id is nil" do
        packet = Fabricate(:lottery_packet, erhaltungsbericht_topic_id: nil)
        expect(packet.has_report?).to be false
      end
    end
  end

  describe "action methods" do
    describe "#mark_winner!" do
      it "sets winner and won_at timestamp" do
        packet = Fabricate(:lottery_packet)
        winner = Fabricate(:user)

        packet.mark_winner!(winner)

        expect(packet.winner_user_id).to eq(winner.id)
        expect(packet.won_at).to be_within(1.second).of(Time.zone.now)
      end

      it "allows custom timestamp" do
        packet = Fabricate(:lottery_packet)
        winner = Fabricate(:user)
        custom_time = 2.days.ago

        packet.mark_winner!(winner, custom_time)

        expect(packet.won_at).to be_within(1.second).of(custom_time)
      end

      it "updates the record in database" do
        packet = Fabricate(:lottery_packet)
        winner = Fabricate(:user)

        packet.mark_winner!(winner)
        packet.reload

        expect(packet.winner_user_id).to eq(winner.id)
        expect(packet.won_at).to be_present
      end
    end

    describe "#mark_collected!" do
      it "sets collected_at timestamp" do
        packet = Fabricate(:lottery_packet)

        packet.mark_collected!

        expect(packet.collected_at).to be_within(1.second).of(Time.zone.now)
      end

      it "allows custom timestamp" do
        packet = Fabricate(:lottery_packet)
        custom_time = 1.week.ago

        packet.mark_collected!(custom_time)

        expect(packet.collected_at).to be_within(1.second).of(custom_time)
      end

      it "updates the record in database" do
        packet = Fabricate(:lottery_packet)

        packet.mark_collected!
        packet.reload

        expect(packet.collected_at).to be_present
      end
    end

    describe "#link_report!" do
      it "sets erhaltungsbericht_topic_id" do
        packet = Fabricate(:lottery_packet)
        report_topic = Fabricate(:topic)

        packet.link_report!(report_topic)

        expect(packet.erhaltungsbericht_topic_id).to eq(report_topic.id)
      end

      it "updates the record in database" do
        packet = Fabricate(:lottery_packet)
        report_topic = Fabricate(:topic)

        packet.link_report!(report_topic)
        packet.reload

        expect(packet.erhaltungsbericht_topic_id).to eq(report_topic.id)
      end
    end
  end

  describe "deletion behavior" do
    context "when post is soft deleted" do
      it "does NOT delete the packet record" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)

        # Soft delete post (using PostDestroyer which handles soft deletion)
        PostDestroyer.new(lottery.topic.user, post).destroy

        # Packet should still exist after soft delete
        expect(described_class.find_by(id: packet.id)).to be_present
      end

      it "packet can still be accessed" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)

        PostDestroyer.new(lottery.topic.user, post).destroy

        found_packet = described_class.find_by(post_id: post.id)
        expect(found_packet).to eq(packet)
      end
    end

    context "when post is hard deleted (destroyed)" do
      it "CASCADE deletes the packet record" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        packet_id = packet.id

        # Hard delete triggers CASCADE
        post.destroy!

        expect(described_class.find_by(id: packet_id)).to be_nil
      end

      it "deletes packet when post is permanently deleted after soft delete" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        packet_id = packet.id
        post_id = post.id

        # Soft delete first
        PostDestroyer.new(lottery.topic.user, post).destroy
        expect(described_class.find_by(id: packet_id)).to be_present

        # Then hard delete
        Post.with_deleted.find(post_id).destroy!

        expect(described_class.find_by(id: packet_id)).to be_nil
      end
    end

    context "when lottery is deleted" do
      it "CASCADE deletes all packets in the lottery" do
        lottery = Fabricate(:lottery)
        post1 = Fabricate(:post, topic: lottery.topic)
        post2 = Fabricate(:post, topic: lottery.topic)
        packet1 = Fabricate(:lottery_packet, lottery: lottery, post: post1)
        packet2 = Fabricate(:lottery_packet, lottery: lottery, post: post2)

        lottery.destroy!

        expect(described_class.find_by(id: packet1.id)).to be_nil
        expect(described_class.find_by(id: packet2.id)).to be_nil
      end
    end

    context "when cascading to lottery tickets" do
      it "deletes associated tickets when packet post is deleted" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        user1 = Fabricate(:user)
        user2 = Fabricate(:user)

        ticket1 = Fabricate(:lottery_ticket, post: post, user: user1)
        ticket2 = Fabricate(:lottery_ticket, post: post, user: user2)

        # Hard delete triggers CASCADE
        post.destroy!

        expect(VzekcVerlosung::LotteryTicket.find_by(id: ticket1.id)).to be_nil
        expect(VzekcVerlosung::LotteryTicket.find_by(id: ticket2.id)).to be_nil
      end
    end

    context "when winner user is deleted" do
      it "NULLIFYs the winner_user_id" do
        winner = Fabricate(:user)
        packet = Fabricate(:lottery_packet, winner_user_id: winner.id, won_at: Time.zone.now)

        # Delete the user
        winner.destroy!

        packet.reload
        expect(packet.winner_user_id).to be_nil
        expect(packet.won_at).to be_present # won_at timestamp is kept
      end
    end

    context "when erhaltungsbericht topic is deleted" do
      it "NULLIFYs the erhaltungsbericht_topic_id" do
        report_topic = Fabricate(:topic)
        packet = Fabricate(:lottery_packet, erhaltungsbericht_topic_id: report_topic.id)

        # Delete the topic
        report_topic.destroy!

        packet.reload
        expect(packet.erhaltungsbericht_topic_id).to be_nil
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

      # User from different packet
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
