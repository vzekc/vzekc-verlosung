# frozen_string_literal: true

class AddReportRemindersSilencedUntilToLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_lottery_packet_winners, :report_reminders_silenced_until, :datetime
  end
end
