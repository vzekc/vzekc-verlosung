# frozen_string_literal: true

class AddStateColumnsToLotteryTables < ActiveRecord::Migration[7.0]
  def change
    # Add state to lottery_packets
    # Tracks what happened to the packet when the lottery was drawn
    # pending: lottery active, not yet drawn
    # no_tickets: lottery drawn, this packet had zero tickets
    # drawn: lottery drawn, winner(s) assigned
    add_column :vzekc_verlosung_lottery_packets, :state, :string, default: "pending", null: false

    # Add fulfillment_state to lottery_packet_winners
    # Tracks fulfillment status for each winner instance
    # won: winner selected, not yet shipped
    # shipped: package shipped to winner
    # received: winner confirmed receipt
    # completed: report written (if required) or fulfilled
    add_column :vzekc_verlosung_lottery_packet_winners, :fulfillment_state, :string,
               default: "won", null: false

    # Add index for filtering by state (use short names to stay under 63 char limit)
    add_index :vzekc_verlosung_lottery_packets, :state, name: "idx_lottery_packets_on_state"
    add_index :vzekc_verlosung_lottery_packet_winners, :fulfillment_state,
              name: "idx_lottery_packet_winners_on_fulfillment_state"
  end
end
