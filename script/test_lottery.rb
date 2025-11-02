# frozen_string_literal: true

# Comprehensive testing utility for lotteries
# Usage: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb <command> [args]
#
# Commands:
#   create <username>           - Create a new test lottery
#   add_participants <topic_id> - Add test participants to lottery
#   publish <topic_id>          - Publish a draft lottery
#   end_early <topic_id>        - End an active lottery early (for testing)
#   clear <topic_id>            - Remove all tickets from lottery
#   delete <topic_id>           - Delete a lottery topic
#   list                        - List all lotteries

def create_lottery(username)
  user = User.find_by(username: username)
  unless user
    puts "✗ User '#{username}' not found"
    exit 1
  end

  category_id = SiteSetting.vzekc_verlosung_category_id
  if category_id.blank?
    puts "✗ vzekc_verlosung_category_id not configured"
    exit 1
  end

  result =
    VzekcVerlosung::CreateLottery.call(
      user: user,
      guardian: Guardian.new(user),
      params: {
        title: "Test Verlosung #{Time.zone.now.strftime("%Y-%m-%d %H:%M")}",
        category_id: category_id.to_i,
        packets: [
          { title: "Commodore 64 mit Datasette" },
          { title: "Amiga 500 Bundle" },
          { title: "Atari ST 1040" },
          { title: "Apple IIe" },
          { title: "ZX Spectrum +2" },
          { title: "IBM PS/2 Model 30" },
        ],
      },
    )

  if result.success?
    topic = result.main_topic
    puts "✓ Created lottery topic #{topic.id}: #{topic.title}"
    puts "  URL: #{topic.url}"
    topic.id
  else
    puts "✗ Failed to create lottery: #{result.inspect}"
    exit 1
  end
end

def add_participants(topic_id, num_users = 30)
  topic = Topic.find(topic_id)
  packet_posts =
    Post
      .where(topic_id: topic.id)
      .order(:post_number)
      .select { |p| p.custom_fields["is_lottery_packet"] == true }

  puts "Found #{packet_posts.count} packets"

  users = User.where("id > ?", 0).where.not(id: [-1, -2]).limit(num_users).to_a
  puts "Adding tickets from #{users.count} users..."

  ticket_count = 0
  users.each do |user|
    num_packets = rand(1..5)
    selected_packets = packet_posts.sample(num_packets)

    selected_packets.each do |packet_post|
      # Users can only have 1 ticket per packet (enforced by uniqueness constraint)
      ticket =
        VzekcVerlosung::LotteryTicket.find_or_create_by(post_id: packet_post.id, user_id: user.id)
      ticket_count += 1 if ticket.previously_new_record?
    end
  end

  puts "✓ Added #{ticket_count} tickets"

  # Show summary
  packet_posts.each do |post|
    tickets = VzekcVerlosung::LotteryTicket.where(post_id: post.id)
    unique_users = tickets.pluck(:user_id).uniq.count
    post.raw.lines.first.to_s.gsub(/^#\s*/, "").strip
    puts "  Packet ##{post.post_number}: #{tickets.count} tickets, #{unique_users} users"
  end
end

def publish_lottery(topic_id)
  topic = Topic.find(topic_id)

  if topic.custom_fields["lottery_state"] != "draft"
    puts "✗ Lottery is not in draft state (current: #{topic.custom_fields["lottery_state"]})"
    exit 1
  end

  topic.custom_fields["lottery_state"] = "active"
  topic.custom_fields["lottery_ends_at"] = 2.weeks.from_now
  topic.save_custom_fields

  puts "✓ Published lottery #{topic_id}"
  puts "  Ends at: #{topic.custom_fields["lottery_ends_at"]}"
end

def end_early(topic_id)
  topic = Topic.find(topic_id)

  unless topic.custom_fields["lottery_state"] == "active"
    puts "✗ Lottery is not active (current: #{topic.custom_fields["lottery_state"]})"
    exit 1
  end

  topic.custom_fields["lottery_ends_at"] = Time.zone.now
  topic.save_custom_fields

  puts "✓ Ended lottery #{topic_id} early"
  puts "  Can now draw winners"
end

def clear_tickets(topic_id)
  topic = Topic.find(topic_id)
  packet_posts =
    Post.where(topic_id: topic.id).select { |p| p.custom_fields["is_lottery_packet"] == true }

  count = 0
  packet_posts.each do |post|
    deleted = VzekcVerlosung::LotteryTicket.where(post_id: post.id).delete_all
    count += deleted
  end

  puts "✓ Deleted #{count} tickets from lottery #{topic_id}"
end

def delete_lottery(topic_id)
  topic = Topic.find(topic_id)

  # Delete all tickets first
  packet_posts =
    Post.where(topic_id: topic.id).select { |p| p.custom_fields["is_lottery_packet"] == true }
  ticket_count = 0
  packet_posts.each do |post|
    ticket_count += VzekcVerlosung::LotteryTicket.where(post_id: post.id).delete_all
  end

  # Delete the topic
  PostDestroyer.new(Discourse.system_user, topic.first_post).destroy

  puts "✓ Deleted lottery topic #{topic_id} (#{ticket_count} tickets removed)"
end

def list_lotteries
  topics =
    Topic
      .joins(:_custom_fields)
      .where(topic_custom_fields: { name: "lottery_state" })
      .order(created_at: :desc)
      .limit(20)

  if topics.empty?
    puts "No lotteries found"
    return
  end

  puts "Recent lotteries:"
  puts ""
  topics.each do |topic|
    state = topic.custom_fields["lottery_state"]
    packet_count =
      Post.where(topic_id: topic.id).count { |p| p.custom_fields["is_lottery_packet"] == true }
    ticket_count =
      VzekcVerlosung::LotteryTicket.joins(:post).where(posts: { topic_id: topic.id }).count

    puts "  [#{topic.id}] #{topic.title}"
    puts "       State: #{state} | Packets: #{packet_count} | Tickets: #{ticket_count}"
  end
end

# Main command dispatcher
command = ARGV[0]

case command
when "create"
  username = ARGV[1] || "hans"
  create_lottery(username)
when "add_participants", "add"
  topic_id = ARGV[1]&.to_i
  unless topic_id
    puts "Usage: test_lottery.rb add_participants <topic_id>"
    exit 1
  end
  num_users = ARGV[2]&.to_i || 30
  add_participants(topic_id, num_users)
when "publish"
  topic_id = ARGV[1]&.to_i
  unless topic_id
    puts "Usage: test_lottery.rb publish <topic_id>"
    exit 1
  end
  publish_lottery(topic_id)
when "end_early", "end"
  topic_id = ARGV[1]&.to_i
  unless topic_id
    puts "Usage: test_lottery.rb end_early <topic_id>"
    exit 1
  end
  end_early(topic_id)
when "clear"
  topic_id = ARGV[1]&.to_i
  unless topic_id
    puts "Usage: test_lottery.rb clear <topic_id>"
    exit 1
  end
  clear_tickets(topic_id)
when "delete"
  topic_id = ARGV[1]&.to_i
  unless topic_id
    puts "Usage: test_lottery.rb delete <topic_id>"
    exit 1
  end
  delete_lottery(topic_id)
when "list"
  list_lotteries
else
  puts "Lottery Testing Utility"
  puts ""
  puts "Usage: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb <command> [args]"
  puts ""
  puts "Commands:"
  puts "  create <username>              - Create test lottery (default: hans)"
  puts "  add_participants <topic_id>    - Add 30 test participants"
  puts "  publish <topic_id>             - Publish draft lottery"
  puts "  end_early <topic_id>           - End active lottery (for testing)"
  puts "  clear <topic_id>               - Remove all tickets"
  puts "  delete <topic_id>              - Delete lottery topic"
  puts "  list                           - List recent lotteries"
  puts ""
  puts "Examples:"
  puts "  test_lottery.rb create hans"
  puts "  test_lottery.rb add_participants 311"
  puts "  test_lottery.rb publish 311"
  puts "  test_lottery.rb end_early 311"
  puts "  test_lottery.rb list"
  exit 1
end
