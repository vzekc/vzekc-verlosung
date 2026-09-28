# frozen_string_literal: true

class AddPublishedAtToLotteries < ActiveRecord::Migration[7.2]
  def up
    add_column :vzekc_verlosung_lotteries, :published_at, :datetime

    # Backfill with the timestamp the drawing has been seeded with so far
    execute <<~SQL
      UPDATE vzekc_verlosung_lotteries
      SET published_at = ends_at - make_interval(days => COALESCE(duration_days, 14))
      WHERE ends_at IS NOT NULL
    SQL
  end

  def down
    remove_column :vzekc_verlosung_lotteries, :published_at
  end
end
