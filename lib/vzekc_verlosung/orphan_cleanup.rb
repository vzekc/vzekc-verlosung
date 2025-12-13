# frozen_string_literal: true

module VzekcVerlosung
  # Cleans up orphaned lottery data at system startup
  #
  # Handles cases where:
  # - Lotteries exist but their topic was deleted
  # - LotteryPackets exist but their post was deleted
  # - LotteryTickets exist but their post was deleted
  module OrphanCleanup
    def self.run
      # Skip if tables don't exist yet (during initial migration)
      return unless tables_exist?

      Rails.logger.info "[VzekcVerlosung] Running orphan cleanup..."

      tickets_deleted = cleanup_orphaned_tickets
      packets_deleted = cleanup_orphaned_packets
      lotteries_deleted = cleanup_orphaned_lotteries

      if tickets_deleted > 0 || packets_deleted > 0 || lotteries_deleted > 0
        Rails.logger.info "[VzekcVerlosung] Orphan cleanup complete: " \
                            "#{lotteries_deleted} lotteries, " \
                            "#{packets_deleted} packets, " \
                            "#{tickets_deleted} tickets removed"
      else
        Rails.logger.info "[VzekcVerlosung] Orphan cleanup complete: no orphans found"
      end
    end

    # Check if all required tables exist
    #
    # @return [Boolean] true if all tables exist
    def self.tables_exist?
      %w[
        vzekc_verlosung_lotteries
        vzekc_verlosung_lottery_packets
        vzekc_verlosung_lottery_tickets
      ].all? { |table| ActiveRecord::Base.connection.table_exists?(table) }
    end

    # Delete lottery tickets where the post no longer exists
    #
    # @return [Integer] Number of tickets deleted
    def self.cleanup_orphaned_tickets
      result = DB.exec(<<~SQL)
        DELETE FROM vzekc_verlosung_lottery_tickets
        WHERE post_id NOT IN (SELECT id FROM posts)
      SQL
      result
    end

    # Delete lottery packets where the post no longer exists
    #
    # @return [Integer] Number of packets deleted
    def self.cleanup_orphaned_packets
      result = DB.exec(<<~SQL)
        DELETE FROM vzekc_verlosung_lottery_packets
        WHERE post_id IS NOT NULL
          AND post_id NOT IN (SELECT id FROM posts)
      SQL
      result
    end

    # Delete lotteries where the topic no longer exists
    #
    # @return [Integer] Number of lotteries deleted
    def self.cleanup_orphaned_lotteries
      result = DB.exec(<<~SQL)
        DELETE FROM vzekc_verlosung_lotteries
        WHERE topic_id NOT IN (SELECT id FROM topics WHERE deleted_at IS NULL)
      SQL
      result
    end
  end
end
