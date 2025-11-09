# frozen_string_literal: true

class MigrateLotteryCustomFieldsToTables < ActiveRecord::Migration[7.0]
  def up
    # Only run migration if tables exist
    return unless table_exists?(:vzekc_verlosung_lotteries)
    return unless table_exists?(:vzekc_verlosung_lottery_packets)

    say "Migrating lottery data from custom_fields to normalized tables..."

    migrated_lotteries = 0
    migrated_packets = 0
    skipped_lotteries = 0
    skipped_packets = 0

    # Find all topics with lottery_state custom field
    lottery_topic_ids =
      DB.query_single(
        "SELECT DISTINCT topic_id FROM topic_custom_fields WHERE name = 'lottery_state'",
      )

    say "Found #{lottery_topic_ids.count} lottery topics to migrate"

    lottery_topic_ids.each do |topic_id|
      # Check if already migrated
      if DB.query_single(
           "SELECT 1 FROM vzekc_verlosung_lotteries WHERE topic_id = ?",
           topic_id,
         ).present?
        skipped_lotteries += 1
        next
      end

      # Get all custom fields for this topic
      custom_fields =
        DB
          .query(
            "SELECT name, value FROM topic_custom_fields WHERE topic_id = ? AND name IN ('lottery_state', 'lottery_ends_at', 'lottery_results', 'lottery_drawn_at', 'lottery_duration_days')",
            topic_id,
          )
          .each_with_object({}) { |row, hash| hash[row.name] = row.value }

      state = custom_fields["lottery_state"]
      next if state.blank?

      # Parse datetime fields
      ends_at = parse_datetime(custom_fields["lottery_ends_at"])
      drawn_at = parse_datetime(custom_fields["lottery_drawn_at"])

      # Parse duration_days - might be stored as string
      duration_days = custom_fields["lottery_duration_days"]&.to_i

      # If duration_days not stored but we have ends_at, calculate from topic creation
      if duration_days.nil? && ends_at.present?
        topic = DB.query_single("SELECT created_at FROM topics WHERE id = ?", topic_id).first
        if topic
          topic_created_at = topic
          duration_days = ((ends_at - topic_created_at) / 1.day).round
          duration_days = nil if duration_days < 7 || duration_days > 28 # Only valid range
        end
      end

      # Parse results JSON
      results = nil
      if custom_fields["lottery_results"].present?
        begin
          results = JSON.parse(custom_fields["lottery_results"])
        rescue JSON::ParserError
          say "  Warning: Could not parse lottery_results JSON for topic #{topic_id}"
        end
      end

      # Insert lottery record
      DB.exec(<<~SQL, topic_id, state, duration_days, ends_at, drawn_at, results&.to_json)
          INSERT INTO vzekc_verlosung_lotteries
            (topic_id, state, duration_days, ends_at, drawn_at, results, created_at, updated_at)
          VALUES (?, ?, ?, ?, ?, ?, NOW(), NOW())
        SQL

      migrated_lotteries += 1

      # Migrate packets for this lottery
      lottery_id =
        DB.query_single(
          "SELECT id FROM vzekc_verlosung_lotteries WHERE topic_id = ?",
          topic_id,
        ).first

      # Find all posts in this topic with is_lottery_packet
      packet_post_ids =
        DB.query_single(
          "SELECT DISTINCT post_id FROM post_custom_fields WHERE name = 'is_lottery_packet' AND value = 't' AND post_id IN (SELECT id FROM posts WHERE topic_id = ?)",
          topic_id,
        )

      packet_post_ids.each do |post_id|
        # Check if already migrated
        if DB.query_single(
             "SELECT 1 FROM vzekc_verlosung_lottery_packets WHERE post_id = ?",
             post_id,
           ).present?
          skipped_packets += 1
          next
        end

        # Get custom fields for this post
        post_custom_fields =
          DB
            .query(
              "SELECT name, value FROM post_custom_fields WHERE post_id = ? AND name IN ('lottery_winner', 'packet_collected_at', 'erhaltungsbericht_topic_id')",
              post_id,
            )
            .each_with_object({}) { |row, hash| hash[row.name] = row.value }

        # Get post content to extract title
        post_raw = DB.query_single("SELECT raw FROM posts WHERE id = ?", post_id).first
        title = extract_title_from_markdown(post_raw) || "Packet ##{post_id}"

        # Find winner user ID from username
        winner_user_id = nil
        won_at = drawn_at # Use lottery's drawn_at as won_at
        if post_custom_fields["lottery_winner"].present?
          winner_username = post_custom_fields["lottery_winner"]
          winner_user_id =
            DB.query_single(
              "SELECT id FROM users WHERE username_lower = LOWER(?)",
              winner_username,
            ).first

          unless winner_user_id
            say "  Warning: Winner user '#{winner_username}' not found for post #{post_id}"
          end
        end

        # Parse collected_at
        collected_at = parse_datetime(post_custom_fields["packet_collected_at"])

        # Parse erhaltungsbericht_topic_id
        erhaltungsbericht_topic_id = post_custom_fields["erhaltungsbericht_topic_id"]&.to_i

        # Insert packet record
        DB.exec(
          <<~SQL,
            INSERT INTO vzekc_verlosung_lottery_packets
              (lottery_id, post_id, title, winner_user_id, won_at, collected_at, erhaltungsbericht_topic_id, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, NOW(), NOW())
          SQL
          lottery_id,
          post_id,
          title,
          winner_user_id,
          won_at,
          collected_at,
          erhaltungsbericht_topic_id,
        )

        migrated_packets += 1
      end
    end

    say "Migration complete!"
    say "  Lotteries: #{migrated_lotteries} migrated, #{skipped_lotteries} skipped (already existed)"
    say "  Packets: #{migrated_packets} migrated, #{skipped_packets} skipped (already existed)"
  end

  def down
    # This migration is destructive - we don't delete the custom_fields
    # But we can remove the migrated data from tables if needed
    say "Rolling back lottery data migration..."
    say "Note: Custom fields are preserved. Only table data will be removed."

    # This is a placeholder - in production you might want to be more selective
    # about what gets deleted (e.g., only delete records that match custom_fields)
    # execute "DELETE FROM vzekc_verlosung_lottery_packets"
    # execute "DELETE FROM vzekc_verlosung_lotteries"

    say "Rollback skipped - manual cleanup recommended if needed"
  end

  private

  def parse_datetime(value)
    return nil if value.blank?
    return value if value.is_a?(Time) || value.is_a?(DateTime)

    begin
      Time.zone.parse(value)
    rescue ArgumentError
      nil
    end
  end

  def extract_title_from_markdown(raw)
    return nil if raw.blank?

    # Extract first heading from markdown (e.g., "# Title")
    match = raw.match(/^#\s+(.+)$/)
    match ? match[1].strip : nil
  end
end
