# frozen_string_literal: true

RSpec.describe VzekcVerlosung::Lottery do
  fab!(:user)
  fab!(:category)

  describe "associations" do
    it { is_expected.to belong_to(:topic) }
    it { is_expected.to have_many(:lottery_packets).dependent(:destroy) }
  end

  describe "validations" do
    subject(:lottery) { Fabricate.build(:lottery) }

    it { is_expected.to validate_presence_of(:topic_id) }
    it { is_expected.to validate_uniqueness_of(:topic_id) }
    it { is_expected.to validate_presence_of(:state) }
    it { is_expected.to validate_inclusion_of(:state).in_array(%w[active finished]) }
    it { is_expected.to validate_presence_of(:drawing_mode) }
    it { is_expected.to validate_inclusion_of(:drawing_mode).in_array(%w[automatic manual]) }

    context "with duration_days" do
      it "validates minimum value" do
        topic = Fabricate(:topic)
        lottery = Fabricate.build(:lottery, topic: topic, duration_days: 6)
        expect(lottery).not_to be_valid
        expect(lottery.errors[:duration_days]).to be_present
      end

      it "validates maximum value" do
        topic = Fabricate(:topic)
        lottery = Fabricate.build(:lottery, topic: topic, duration_days: 29)
        expect(lottery).not_to be_valid
        expect(lottery.errors[:duration_days]).to be_present
      end

      it "allows values in range" do
        topic = Fabricate(:topic)
        lottery = Fabricate.build(:lottery, topic: topic, duration_days: 14)
        expect(lottery).to be_valid
      end

      it "allows nil" do
        topic = Fabricate(:topic)
        lottery = Fabricate.build(:lottery, topic: topic, duration_days: nil)
        expect(lottery).to be_valid
      end
    end
  end

  describe "scopes" do
    let!(:active_lottery) { Fabricate(:lottery, state: "active", ends_at: 2.days.from_now) }
    let!(:finished_lottery) { Fabricate(:lottery, state: "finished") }
    let!(:ready_lottery) do
      Fabricate(:lottery, state: "active", ends_at: 1.hour.ago, drawn_at: nil)
    end
    let!(:drawn_lottery) do
      Fabricate(:lottery, state: "active", ends_at: 1.hour.ago, drawn_at: Time.zone.now)
    end

    describe ".active" do
      it "returns only active lotteries" do
        results =
          described_class.active.where(id: [active_lottery.id, ready_lottery.id, drawn_lottery.id])
        expect(results).to contain_exactly(active_lottery, ready_lottery, drawn_lottery)
      end
    end

    describe ".finished" do
      it "returns only finished lotteries" do
        results = described_class.finished.where(id: finished_lottery.id)
        expect(results).to contain_exactly(finished_lottery)
      end
    end

    describe ".ready_to_draw" do
      it "returns active lotteries that have ended but not been drawn" do
        results = described_class.ready_to_draw.where(id: ready_lottery.id)
        expect(results).to contain_exactly(ready_lottery)
      end
    end

    describe ".ending_soon" do
      let!(:ending_soon) { Fabricate(:lottery, state: "active", ends_at: 12.hours.from_now) }

      it "returns active lotteries ending within 1 day" do
        results = described_class.ending_soon.where(id: ending_soon.id)
        expect(results).to contain_exactly(ending_soon)
      end

      it "excludes lotteries ending later" do
        results = described_class.ending_soon.where(id: active_lottery.id)
        expect(results).to be_empty
      end
    end
  end

  describe "state helpers" do
    it "#active? returns true for active state" do
      lottery = Fabricate(:lottery, state: "active")
      expect(lottery.active?).to be true
      expect(lottery.finished?).to be false
    end

    it "#finished? returns true for finished state" do
      lottery = Fabricate(:lottery, state: "finished")
      expect(lottery.finished?).to be true
      expect(lottery.active?).to be false
    end

    it "#drawn? returns true when drawn_at is present" do
      lottery = Fabricate(:lottery, drawn_at: Time.zone.now)
      expect(lottery.drawn?).to be true
    end

    it "#drawn? returns false when drawn_at is nil" do
      lottery = Fabricate(:lottery, drawn_at: nil)
      expect(lottery.drawn?).to be false
    end
  end

  describe "drawing mode helpers" do
    it "#automatic_drawing? returns true for automatic mode" do
      lottery = Fabricate(:lottery, drawing_mode: "automatic")
      expect(lottery.automatic_drawing?).to be true
      expect(lottery.manual_drawing?).to be false
    end

    it "#manual_drawing? returns true for manual mode" do
      lottery = Fabricate(:lottery, drawing_mode: "manual")
      expect(lottery.manual_drawing?).to be true
      expect(lottery.automatic_drawing?).to be false
    end
  end

  describe "state transitions" do
    describe "#finish!" do
      it "changes state from active to finished" do
        lottery = Fabricate(:lottery, state: "active")

        lottery.finish!

        expect(lottery.state).to eq("finished")
      end

      it "updates the record in database" do
        lottery = Fabricate(:lottery, state: "active")

        lottery.finish!
        lottery.reload

        expect(lottery.state).to eq("finished")
      end
    end

    describe "#mark_drawn!" do
      it "sets drawn_at timestamp and stores results" do
        lottery = Fabricate(:lottery, state: "active")
        results = { "winner" => "alice", "seed" => "abc123" }

        lottery.mark_drawn!(results)

        expect(lottery.drawn_at).to be_within(1.second).of(Time.zone.now)
        expect(lottery.results).to eq(results)
      end

      it "updates the record in database" do
        lottery = Fabricate(:lottery, state: "active")
        results = { "winner" => "alice", "seed" => "abc123" }

        lottery.mark_drawn!(results)
        lottery.reload

        expect(lottery.drawn_at).to be_present
        expect(lottery.results).to eq(results)
      end
    end
  end

  describe "deletion behavior" do
    context "when topic is soft deleted" do
      it "does NOT delete the lottery record" do
        topic = Fabricate(:topic, user: user, category: category)
        lottery = Fabricate(:lottery, topic: topic)

        # Soft delete (sets deleted_at)
        topic.trash!(user)

        expect(described_class.find_by(id: lottery.id)).to be_present
        # Topic still exists but is soft deleted
        soft_deleted_topic = Topic.with_deleted.find(topic.id)
        expect(soft_deleted_topic.deleted_at).to be_present
      end

      it "lottery can still be accessed via find_by" do
        topic = Fabricate(:topic, user: user, category: category)
        lottery = Fabricate(:lottery, topic: topic)

        topic.trash!(user)

        found_lottery = described_class.find_by(topic_id: topic.id)
        expect(found_lottery).to eq(lottery)
      end
    end

    context "when topic is hard deleted (destroyed)" do
      it "CASCADE deletes the lottery record" do
        topic = Fabricate(:topic, user: user, category: category)
        lottery = Fabricate(:lottery, topic: topic)
        lottery_id = lottery.id

        # Hard delete triggers CASCADE
        topic.destroy!

        expect(described_class.find_by(id: lottery_id)).to be_nil
      end

      it "deletes lottery when topic is permanently deleted after trash" do
        topic = Fabricate(:topic, user: user, category: category)
        lottery = Fabricate(:lottery, topic: topic)
        lottery_id = lottery.id

        # Soft delete first
        topic.trash!(user)
        expect(described_class.find_by(id: lottery_id)).to be_present

        # Then hard delete
        Topic.with_deleted.find(topic.id).destroy!

        expect(described_class.find_by(id: lottery_id)).to be_nil
      end
    end

    context "when cascading to lottery packets" do
      it "deletes associated lottery_packets when lottery is deleted" do
        topic = Fabricate(:topic, user: user, category: category)
        lottery = Fabricate(:lottery, topic: topic)
        post = Fabricate(:post, topic: topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        packet_id = packet.id

        # Hard delete topic triggers CASCADE to lottery, then to packets
        topic.destroy!

        expect(VzekcVerlosung::LotteryPacket.find_by(id: packet_id)).to be_nil
      end

      it "deletes multiple packets when lottery is deleted" do
        topic = Fabricate(:topic, user: user, category: category)
        lottery = Fabricate(:lottery, topic: topic)
        post1 = Fabricate(:post, topic: topic)
        post2 = Fabricate(:post, topic: topic)
        packet1 = Fabricate(:lottery_packet, lottery: lottery, post: post1)
        packet2 = Fabricate(:lottery_packet, lottery: lottery, post: post2)

        topic.destroy!

        expect(VzekcVerlosung::LotteryPacket.find_by(id: packet1.id)).to be_nil
        expect(VzekcVerlosung::LotteryPacket.find_by(id: packet2.id)).to be_nil
      end
    end
  end

  describe "#participants" do
    it "returns unique users who bought tickets for any packet" do
      lottery = Fabricate(:lottery)
      post1 = Fabricate(:post, topic: lottery.topic)
      post2 = Fabricate(:post, topic: lottery.topic)
      packet1 = Fabricate(:lottery_packet, lottery: lottery, post: post1)
      packet2 = Fabricate(:lottery_packet, lottery: lottery, post: post2)

      user1 = Fabricate(:user)
      user2 = Fabricate(:user)
      user3 = Fabricate(:user)

      # User1 draws tickets for both packets
      Fabricate(:lottery_ticket, post: post1, user: user1)
      Fabricate(:lottery_ticket, post: post2, user: user1)

      # User2 draws ticket for packet1
      Fabricate(:lottery_ticket, post: post1, user: user2)

      # User3 draws ticket for packet2
      Fabricate(:lottery_ticket, post: post2, user: user3)

      participants = lottery.participants
      expect(participants).to contain_exactly(user1, user2, user3)
    end
  end

  describe "#participant_count" do
    it "returns count of unique participants" do
      lottery = Fabricate(:lottery)
      post1 = Fabricate(:post, topic: lottery.topic)
      post2 = Fabricate(:post, topic: lottery.topic)
      packet1 = Fabricate(:lottery_packet, lottery: lottery, post: post1)
      packet2 = Fabricate(:lottery_packet, lottery: lottery, post: post2)

      user1 = Fabricate(:user)
      user2 = Fabricate(:user)

      Fabricate(:lottery_ticket, post: post1, user: user1)
      Fabricate(:lottery_ticket, post: post2, user: user1)
      Fabricate(:lottery_ticket, post: post1, user: user2)

      expect(lottery.participant_count).to eq(2)
    end
  end
end
