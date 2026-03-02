# frozen_string_literal: true

require "rails_helper"

describe Jobs::VzekcVerlosungNotifyLotteryEnded do
  fab!(:owner) { Fabricate(:user, trust_level: TrustLevel[2]) }
  fab!(:topic) { Fabricate(:topic, user: owner) }

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#execute" do
    context "when plugin is disabled" do
      before { SiteSetting.vzekc_verlosung_enabled = false }

      it "does nothing" do
        lottery =
          VzekcVerlosung::Lottery.create!(
            topic_id: topic.id,
            state: "active",
            duration_days: 14,
            ends_at: 1.hour.ago,
          )

        expect { described_class.new.execute(lottery_id: lottery.id) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end

    context "when lottery_id is nil" do
      it "does nothing" do
        expect { described_class.new.execute(lottery_id: nil) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end

    context "when lottery does not exist" do
      it "does nothing" do
        expect { described_class.new.execute(lottery_id: 999_999) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end

    context "when lottery is still active and has not ended" do
      it "does nothing" do
        lottery =
          VzekcVerlosung::Lottery.create!(
            topic_id: topic.id,
            state: "active",
            duration_days: 14,
            ends_at: 1.day.from_now,
          )

        expect { described_class.new.execute(lottery_id: lottery.id) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end

    context "when lottery is already drawn" do
      it "does nothing" do
        lottery =
          VzekcVerlosung::Lottery.create!(
            topic_id: topic.id,
            state: "active",
            duration_days: 14,
            ends_at: 1.hour.ago,
            drawn_at: 30.minutes.ago,
          )

        expect { described_class.new.execute(lottery_id: lottery.id) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end

    context "when lottery is finished (not active)" do
      it "does nothing" do
        lottery =
          VzekcVerlosung::Lottery.create!(
            topic_id: topic.id,
            state: "finished",
            duration_days: 14,
            ends_at: 1.hour.ago,
          )

        expect { described_class.new.execute(lottery_id: lottery.id) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end

    context "when lottery is ready to draw" do
      let!(:lottery) do
        VzekcVerlosung::Lottery.create!(
          topic_id: topic.id,
          state: "active",
          duration_days: 14,
          ends_at: 1.hour.ago,
        )
      end

      it "creates a notification log entry" do
        expect { described_class.new.execute(lottery_id: lottery.id) }.to change {
          VzekcVerlosung::NotificationLog.count
        }.by(1)

        log = VzekcVerlosung::NotificationLog.last
        expect(log.notification_type).to eq("lottery_ended")
        expect(log.delivery_method).to eq("pm")
        expect(log.recipient_user_id).to eq(owner.id)
        expect(log.lottery_id).to eq(lottery.id)
        expect(log.success).to eq(true)
      end

      it "sends a PM to the owner" do
        expect { described_class.new.execute(lottery_id: lottery.id) }.to change {
          Topic.where(archetype: Archetype.private_message).count
        }.by(1)

        pm = Topic.where(archetype: Archetype.private_message).order(created_at: :desc).first
        expect(pm.topic_allowed_users.map(&:user_id)).to include(owner.id)
      end
    end

    context "when notification was already sent (dedup)" do
      let!(:lottery) do
        VzekcVerlosung::Lottery.create!(
          topic_id: topic.id,
          state: "active",
          duration_days: 14,
          ends_at: 1.hour.ago,
        )
      end

      before do
        VzekcVerlosung::NotificationLog.create!(
          recipient_user_id: owner.id,
          notification_type: "lottery_ended",
          delivery_method: "pm",
          lottery_id: lottery.id,
          success: true,
        )
      end

      it "does not send a duplicate notification" do
        expect { described_class.new.execute(lottery_id: lottery.id) }.not_to change {
          VzekcVerlosung::NotificationLog.count
        }
      end
    end
  end
end
