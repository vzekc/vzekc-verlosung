# frozen_string_literal: true

RSpec.describe VzekcVerlosung::LotteryTicket do
  fab!(:user)
  fab!(:post)

  describe "associations" do
    it { is_expected.to belong_to(:post) }
    it { is_expected.to belong_to(:user) }
  end

  describe "validations" do
    subject(:ticket) { Fabricate.build(:lottery_ticket) }

    it { is_expected.to validate_presence_of(:post_id) }
    it { is_expected.to validate_presence_of(:user_id) }

    context "uniqueness" do
      it "validates uniqueness of post_id scoped to user_id" do
        existing_ticket = Fabricate(:lottery_ticket)

        duplicate_ticket =
          Fabricate.build(:lottery_ticket, post: existing_ticket.post, user: existing_ticket.user)

        expect(duplicate_ticket).not_to be_valid
        expect(duplicate_ticket.errors[:post_id]).to be_present
      end

      it "allows same user to buy tickets for different posts" do
        user = Fabricate(:user)
        post1 = Fabricate(:post)
        post2 = Fabricate(:post)

        ticket1 = Fabricate(:lottery_ticket, user: user, post: post1)
        ticket2 = Fabricate.build(:lottery_ticket, user: user, post: post2)

        expect(ticket2).to be_valid
      end

      it "allows different users to buy tickets for same post" do
        post = Fabricate(:post)
        user1 = Fabricate(:user)
        user2 = Fabricate(:user)

        ticket1 = Fabricate(:lottery_ticket, user: user1, post: post)
        ticket2 = Fabricate.build(:lottery_ticket, user: user2, post: post)

        expect(ticket2).to be_valid
      end
    end
  end

  describe "#lottery_packet" do
    it "returns the associated lottery packet" do
      lottery = Fabricate(:lottery)
      post = Fabricate(:post, topic: lottery.topic)
      packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
      ticket = Fabricate(:lottery_ticket, post: post, user: Fabricate(:user))

      expect(ticket.lottery_packet).to eq(packet)
    end

    it "returns nil if no packet exists for the post" do
      post = Fabricate(:post)
      ticket = Fabricate(:lottery_ticket, post: post, user: Fabricate(:user))

      expect(ticket.lottery_packet).to be_nil
    end
  end

  describe "deletion behavior" do
    context "when post is soft deleted" do
      it "does NOT delete the ticket record" do
        lottery = Fabricate(:lottery)
        post = Fabricate(:post, topic: lottery.topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        ticket = Fabricate(:lottery_ticket, post: post, user: Fabricate(:user))

        # Soft delete post (using PostDestroyer which handles soft deletion)
        PostDestroyer.new(lottery.topic.user, post).destroy

        # Ticket should still exist after soft delete
        expect(described_class.find_by(id: ticket.id)).to be_present
      end
    end

    context "when post is hard deleted (destroyed)" do
      it "deletes the ticket record due to foreign key constraint" do
        post = Fabricate(:post)
        ticket = Fabricate(:lottery_ticket, post: post, user: Fabricate(:user))
        ticket_id = ticket.id

        # Hard delete triggers foreign key action
        post.destroy!

        expect(described_class.find_by(id: ticket_id)).to be_nil
      end

      it "deletes multiple tickets for the same post" do
        post = Fabricate(:post)
        user1 = Fabricate(:user)
        user2 = Fabricate(:user)
        user3 = Fabricate(:user)

        ticket1 = Fabricate(:lottery_ticket, post: post, user: user1)
        ticket2 = Fabricate(:lottery_ticket, post: post, user: user2)
        ticket3 = Fabricate(:lottery_ticket, post: post, user: user3)

        post.destroy!

        expect(described_class.find_by(id: ticket1.id)).to be_nil
        expect(described_class.find_by(id: ticket2.id)).to be_nil
        expect(described_class.find_by(id: ticket3.id)).to be_nil
      end
    end

    context "when user is deleted" do
      it "deletes all tickets for that user" do
        user = Fabricate(:user)
        post1 = Fabricate(:post)
        post2 = Fabricate(:post)

        ticket1 = Fabricate(:lottery_ticket, user: user, post: post1)
        ticket2 = Fabricate(:lottery_ticket, user: user, post: post2)

        # Delete user
        user.destroy!

        expect(described_class.find_by(id: ticket1.id)).to be_nil
        expect(described_class.find_by(id: ticket2.id)).to be_nil
      end

      it "does not affect tickets from other users" do
        user1 = Fabricate(:user)
        user2 = Fabricate(:user)
        post = Fabricate(:post)

        ticket1 = Fabricate(:lottery_ticket, user: user1, post: post)
        ticket2 = Fabricate(:lottery_ticket, user: user2, post: post)

        user1.destroy!

        expect(described_class.find_by(id: ticket1.id)).to be_nil
        expect(described_class.find_by(id: ticket2.id)).to be_present
      end
    end

    context "cascade from topic deletion" do
      it "deletes all tickets when lottery topic and posts are deleted" do
        lottery = Fabricate(:lottery)
        topic = lottery.topic
        post1 = Fabricate(:post, topic: topic)
        post2 = Fabricate(:post, topic: topic)

        packet1 = Fabricate(:lottery_packet, lottery: lottery, post: post1)
        packet2 = Fabricate(:lottery_packet, lottery: lottery, post: post2)

        user1 = Fabricate(:user)
        user2 = Fabricate(:user)

        ticket1 = Fabricate(:lottery_ticket, post: post1, user: user1)
        ticket2 = Fabricate(:lottery_ticket, post: post2, user: user2)

        ticket1_id = ticket1.id
        ticket2_id = ticket2.id

        # Hard delete posts (which triggers CASCADE to tickets)
        post1.destroy!
        post2.destroy!

        # Tickets should be deleted because posts are deleted via CASCADE
        expect(described_class.find_by(id: ticket1_id)).to be_nil
        expect(described_class.find_by(id: ticket2_id)).to be_nil
      end

      it "preserves tickets during soft delete of topic" do
        lottery = Fabricate(:lottery)
        topic = lottery.topic
        post = Fabricate(:post, topic: topic)
        packet = Fabricate(:lottery_packet, lottery: lottery, post: post)
        ticket = Fabricate(:lottery_ticket, post: post, user: Fabricate(:user))

        # Soft delete topic
        topic.trash!(topic.user)

        expect(described_class.find_by(id: ticket.id)).to be_present
      end
    end
  end

  describe "querying" do
    it "can find all tickets for a user" do
      user = Fabricate(:user)
      post1 = Fabricate(:post)
      post2 = Fabricate(:post)
      other_user = Fabricate(:user)

      ticket1 = Fabricate(:lottery_ticket, user: user, post: post1)
      ticket2 = Fabricate(:lottery_ticket, user: user, post: post2)
      ticket3 = Fabricate(:lottery_ticket, user: other_user, post: post1)

      user_tickets = described_class.where(user_id: user.id)

      expect(user_tickets).to contain_exactly(ticket1, ticket2)
    end

    it "can find all tickets for a post" do
      post = Fabricate(:post)
      other_post = Fabricate(:post)
      user1 = Fabricate(:user)
      user2 = Fabricate(:user)

      ticket1 = Fabricate(:lottery_ticket, user: user1, post: post)
      ticket2 = Fabricate(:lottery_ticket, user: user2, post: post)
      ticket3 = Fabricate(:lottery_ticket, user: user1, post: other_post)

      post_tickets = described_class.where(post_id: post.id)

      expect(post_tickets).to contain_exactly(ticket1, ticket2)
    end

    it "can count tickets for a post" do
      post = Fabricate(:post)
      user1 = Fabricate(:user)
      user2 = Fabricate(:user)
      user3 = Fabricate(:user)

      Fabricate(:lottery_ticket, user: user1, post: post)
      Fabricate(:lottery_ticket, user: user2, post: post)
      Fabricate(:lottery_ticket, user: user3, post: post)

      expect(described_class.where(post_id: post.id).count).to eq(3)
    end
  end
end
