# frozen_string_literal: true

class BackfillAbholerpaketPosts < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    # Find all Abholerpakete without posts and create posts for them
    VzekcVerlosung::LotteryPacket
      .where(abholerpaket: true, post_id: nil)
      .find_each do |packet|
        begin
          lottery = VzekcVerlosung::Lottery.find(packet.lottery_id)
          topic = Topic.find(lottery.topic_id)
          user = topic.user

          # Create a post for this Abholerpaket
          display_title = "Paket 0: #{packet.title}"
          raw_content = "# #{display_title}\n\n"

          post_creator =
            PostCreator.new(user, raw: raw_content, topic_id: topic.id, skip_validations: true)

          post = post_creator.create

          if post&.persisted?
            # Update the lottery packet with the post_id
            packet.update!(post_id: post.id)
          else
            Rails.logger.error "Failed to create post for Abholerpaket #{packet.id}: #{post_creator.errors.full_messages.join(", ")}"
          end
        rescue ActiveRecord::RecordNotFound => e
          # Topic or lottery was deleted, clean up orphaned packet
          Rails.logger.warn "Deleting orphaned Abholerpaket #{packet.id}: #{e.message}"
          packet.destroy
        end
      end

    # Now enforce NOT NULL constraint on post_id (only applies to remaining packets)
    change_column_null :vzekc_verlosung_lottery_packets, :post_id, false
  end

  def down
    # Make post_id nullable again (reverses the constraint change)
    change_column_null :vzekc_verlosung_lottery_packets, :post_id, true
  end
end
