# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungEndedReminder do
  fab!(:owner) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:topic) { Fabricate(:topic, user: owner) }

  before do
    SiteSetting.vzekc_verlosung_enabled = true
    SiteSetting.vzekc_verlosung_reminder_hour = 7
  end

  def create_lottery(**attrs)
    VzekcVerlosung::Lottery.create!(
      { topic_id: topic.id, state: "active", duration_days: 14, ends_at: 1.hour.ago }.merge(attrs),
    )
  end

  describe "#execute" do
    context "when an ended lottery draws automatically on end" do
      before { freeze_time Time.zone.now.change(hour: 12) }

      it "draws it outside the reminder hour" do
        lottery = create_lottery(auto_draw: true)
        allow(VzekcVerlosung::DrawLottery).to receive(:auto_draw!).and_return(true)

        described_class.new.execute({})

        expect(VzekcVerlosung::DrawLottery).to have_received(:auto_draw!).with(lottery)
        expect(VzekcVerlosung::NotificationLog.count).to eq(0)
      end
    end

    context "when an ended lottery is drawn manually" do
      it "does not draw it" do
        freeze_time Time.zone.now.change(hour: 12)
        create_lottery(auto_draw: false)
        allow(VzekcVerlosung::DrawLottery).to receive(:auto_draw!)

        described_class.new.execute({})

        expect(VzekcVerlosung::DrawLottery).not_to have_received(:auto_draw!)
      end

      it "reminds the owner to draw at the reminder hour" do
        freeze_time Time.zone.now.change(hour: 7)
        lottery = create_lottery(auto_draw: false)
        packet =
          VzekcVerlosung::LotteryPacket.create!(
            lottery_id: lottery.id,
            post_id: Fabricate(:post, topic: topic).id,
            ordinal: 1,
            title: "Packet 1",
            quantity: 1,
          )
        VzekcVerlosung::LotteryTicket.create!(post_id: packet.post_id, user_id: owner.id)

        described_class.new.execute({})

        expect(
          VzekcVerlosung::NotificationLog.exists?(
            notification_type: "ended_reminder",
            recipient_user_id: owner.id,
          ),
        ).to eq(true)
      end
    end
  end
end
