# frozen_string_literal: true

# Script to delete all lotteries and their associated data
# Run with: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/delete_all_lotteries.rb

puts "=" * 80
puts "DELETE ALL LOTTERIES"
puts "=" * 80
puts ""

# Safety check - only run in development
if Rails.env.production?
  puts "ERROR: This script cannot be run in production!"
  puts "If you really need to delete lotteries in production, modify this script."
  exit 1
end

puts "Environment: #{Rails.env}"
puts "Database: #{ActiveRecord::Base.connection_db_config.database}"
puts ""

# Find all lottery topics
lottery_topics =
  Topic
    .where(deleted_at: nil)
    .joins(:_custom_fields)
    .where(topic_custom_fields: { name: "lottery_state" })
    .distinct

if lottery_topics.empty?
  puts "No lotteries found."
  exit 0
end

puts "Found #{lottery_topics.count} lottery topics:"
puts "-" * 80

lottery_topics.each do |topic|
  state = topic.custom_fields["lottery_state"]
  puts "Topic ##{topic.id}: #{topic.title}"
  puts "  Creator: #{topic.user.username}"
  puts "  State: #{state}"
  puts "  Created: #{topic.created_at}"

  # Count tickets
  ticket_count =
    VzekcVerlosung::LotteryTicket
      .joins(:post)
      .where(posts: { topic_id: topic.id })
      .count

  # Count packet posts
  packet_count = Post.where(topic_id: topic.id).count { |p| p.custom_fields["is_lottery_packet"] }

  puts "  Tickets: #{ticket_count}"
  puts "  Packets: #{packet_count}"
  puts ""
end

puts "=" * 80
puts "WARNING: This will permanently delete:"
puts "  - #{lottery_topics.count} lottery topics"
puts "  - All associated packet posts"
puts "  - All lottery tickets"
puts "  - All custom fields"
puts "=" * 80
puts ""

print "Type 'DELETE' to confirm: "
confirmation = STDIN.gets.chomp

if confirmation != "DELETE"
  puts "Cancelled."
  exit 0
end

puts ""
puts "Deleting lotteries..."
puts ""

deleted_count = 0
ticket_count = 0
post_count = 0

lottery_topics.each do |topic|
  puts "Deleting Topic ##{topic.id}: #{topic.title}..."

  # Delete all tickets for this lottery
  tickets =
    VzekcVerlosung::LotteryTicket
      .joins(:post)
      .where(posts: { topic_id: topic.id })

  tickets_deleted = tickets.count
  tickets.destroy_all
  ticket_count += tickets_deleted
  puts "  Deleted #{tickets_deleted} tickets"

  # Delete all posts in the topic (including packets)
  posts = Post.where(topic_id: topic.id)
  posts_deleted = posts.count
  posts.each(&:destroy)
  post_count += posts_deleted
  puts "  Deleted #{posts_deleted} posts"

  # Delete the topic itself
  topic.destroy
  deleted_count += 1
  puts "  Deleted topic"
  puts ""
end

puts "=" * 80
puts "COMPLETE"
puts "=" * 80
puts "Deleted:"
puts "  Topics: #{deleted_count}"
puts "  Posts: #{post_count}"
puts "  Tickets: #{ticket_count}"
puts ""
