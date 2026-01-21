# frozen_string_literal: true

class BackfillStateColumns < ActiveRecord::Migration[7.0]
  def up
    # Backfill LotteryPacket states
    # Packets with winners -> drawn
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packets
      SET state = 'drawn'
      WHERE id IN (
        SELECT DISTINCT lottery_packet_id FROM vzekc_verlosung_lottery_packet_winners
      )
    SQL

    # Packets from finished lotteries without winners -> no_tickets
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packets
      SET state = 'no_tickets'
      WHERE state = 'pending'
      AND lottery_id IN (
        SELECT id FROM vzekc_verlosung_lotteries
        WHERE state = 'finished' AND drawn_at IS NOT NULL
      )
      AND id NOT IN (
        SELECT DISTINCT lottery_packet_id FROM vzekc_verlosung_lottery_packet_winners
      )
    SQL

    # Backfill LotteryPacketWinner fulfillment_states
    # Winners with erhaltungsbericht_topic_id -> completed
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packet_winners
      SET fulfillment_state = 'completed'
      WHERE erhaltungsbericht_topic_id IS NOT NULL
    SQL

    # Winners with collected_at but no report -> received (unless report not required)
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packet_winners
      SET fulfillment_state = 'received'
      WHERE fulfillment_state = 'won'
      AND collected_at IS NOT NULL
      AND erhaltungsbericht_topic_id IS NULL
      AND lottery_packet_id IN (
        SELECT id FROM vzekc_verlosung_lottery_packets
        WHERE erhaltungsbericht_required = true
      )
    SQL

    # Winners with collected_at where report not required -> completed
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packet_winners
      SET fulfillment_state = 'completed'
      WHERE fulfillment_state = 'won'
      AND collected_at IS NOT NULL
      AND lottery_packet_id IN (
        SELECT id FROM vzekc_verlosung_lottery_packets
        WHERE erhaltungsbericht_required = false
      )
    SQL

    # Winners with shipped_at but not collected -> shipped
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packet_winners
      SET fulfillment_state = 'shipped'
      WHERE fulfillment_state = 'won'
      AND shipped_at IS NOT NULL
      AND collected_at IS NULL
    SQL
  end

  def down
    # Reset all states to defaults (reversible for safety)
    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packets
      SET state = 'pending'
    SQL

    execute <<~SQL
      UPDATE vzekc_verlosung_lottery_packet_winners
      SET fulfillment_state = 'won'
    SQL
  end
end
