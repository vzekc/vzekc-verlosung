# frozen_string_literal: true

# NOTE: This migration removes deprecated columns that are now stored in
# the lottery_packet_winners junction table. The columns are ignored via
# self.ignored_columns in the LotteryPacket model.
#
# The actual column removal is deferred - this migration is a no-op to
# avoid Discourse's column removal protection. The columns will be removed
# in a future post-deployment migration after the code is fully deployed.
class RemoveWinnerColumnsFromLotteryPackets < ActiveRecord::Migration[7.2]
  def up
    # No-op: Column removal is deferred to post-deployment.
    # The LotteryPacket model uses ignored_columns to hide these columns.
    # Columns to be removed in post-deploy migration:
    # - winner_user_id
    # - won_at
    # - collected_at
    # - erhaltungsbericht_topic_id
  end

  def down
    # No-op: Columns were never actually removed
  end
end
