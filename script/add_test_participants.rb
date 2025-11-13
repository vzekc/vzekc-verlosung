# frozen_string_literal: true

# Add test participants to lottery packets
# Usage: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/add_test_participants.rb <topic_id>

topic_id = ARGV[0]&.to_i || 311

# Get all packet posts from topic
topic = Topic.find(topic_id)
packet_posts =
  Post
    .where(topic_id: topic.id)
    .order(:post_number)
    .select { |p| p.custom_fields["is_lottery_packet"] == true }

puts "Found #{packet_posts.count} packet posts in topic #{topic_id}"

# Get first 30 users (excluding system users)
users = User.where("id > ?", 0).where.not(id: [-1, -2]).limit(30).to_a
puts "Found #{users.count} users"

# Add tickets for each user to random packets (1 ticket per user per packet)
ticket_count = 0
users.each do |user|
  # Pick 1-5 random packets
  num_packets = rand(1..5)
  selected_packets = packet_posts.sample(num_packets)

  selected_packets.each do |packet_post|
    # Users can only have 1 ticket per packet (enforced by uniqueness constraint)
    ticket =
      VzekcVerlosung::LotteryTicket.find_or_create_by(post_id: packet_post.id, user_id: user.id)
    if ticket.previously_new_record?
      ticket_count += 1
      puts "  ✓ Added ticket for #{user.username} to packet ##{packet_post.post_number}"
    end
  end
end

puts ""
puts "✓ Added #{ticket_count} total tickets from #{users.count} users"

# Show summary per packet
puts ""
puts "Packet Summary:"
packet_posts.each do |post|
  tickets = VzekcVerlosung::LotteryTicket.where(post_id: post.id)
  unique_users = tickets.pluck(:user_id).uniq.count
  title = post.raw.lines.first.to_s.gsub(/^#\s*/, "").strip
  puts "  Packet ##{post.post_number} (#{title}): #{tickets.count} tickets from #{unique_users} users"
end
