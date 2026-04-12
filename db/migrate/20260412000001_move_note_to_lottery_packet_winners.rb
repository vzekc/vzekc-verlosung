# frozen_string_literal: true

class MoveNoteToLotteryPacketWinners < ActiveRecord::Migration[7.2]
  def up
    add_column :vzekc_verlosung_lottery_packet_winners, :note, :text, null: true

    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packet_winners lpw
         SET note = lp.note
        FROM vzekc_verlosung_lottery_packets lp
       WHERE lpw.lottery_packet_id = lp.id
         AND lp.note IS NOT NULL
    SQL
  end

  def down
    remove_column :vzekc_verlosung_lottery_packet_winners, :note
  end
end
