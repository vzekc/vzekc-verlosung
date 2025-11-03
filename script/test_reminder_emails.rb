# frozen_string_literal: true

# Test script for reminder emails
# Run with: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_reminder_emails.rb

puts "=== Testing Reminder Emails ==="
puts ""

# Check settings
puts "Settings:"
puts "  Plugin enabled: #{SiteSetting.vzekc_verlosung_enabled}"
puts "  Draft reminders enabled: #{SiteSetting.vzekc_verlosung_draft_reminder_enabled}"
puts "  Ended reminders enabled: #{SiteSetting.vzekc_verlosung_ended_reminder_enabled}"
puts "  Lottery category: #{SiteSetting.vzekc_verlosung_category_id}"
puts ""

# Get random users for testing - use members of Vereinsmitglied group
puts "=== Creating Test Lotteries ==="
group = Group.find_by(name: "Vereinsmitglied")

if group
  random_users = group.users.order("RANDOM()").limit(2).to_a
  puts "Found #{random_users.size} users from 'Vereinsmitglied' group"

  if random_users.size < 2
    puts "  WARNING: Only #{random_users.size} user(s) in group, using available user(s)"
    if random_users.size == 1
      random_users = [random_users[0], random_users[0]] # Use same user twice
    elsif random_users.empty?
      puts "  ERROR: No users found in 'Vereinsmitglied' group"
      puts "  Falling back to admin users..."
      random_users = User.where(admin: true).limit(2).to_a
    end
  end
else
  puts "  WARNING: 'Vereinsmitglied' group not found, using admin users instead"
  random_users = User.where(admin: true).limit(2).to_a
end

if random_users.size < 2 && random_users.size == 1
  random_users = [random_users[0], random_users[0]]
elsif random_users.empty?
  puts "  ERROR: No suitable users found. Cannot create test lotteries."
  exit 1
end

# Get lottery category
category_id = SiteSetting.vzekc_verlosung_category_id.to_i
category = Category.find_by(id: category_id)

unless category
  puts "Lottery category not found! Using default category..."
  category = Category.where(read_restricted: false).first
  puts "  Using category: #{category.name} (id: #{category.id})"
end

# Create draft lottery
draft_user = random_users[0]
puts ""
puts "Creating draft lottery for user: #{draft_user.username}"

draft_result =
  VzekcVerlosung::CreateLottery.call(
    params: {
      title: "TEST Draft Lottery #{Time.now.to_i}",
      duration_days: 7,
      category_id: category.id,
      packets: [{ title: "Test Packet 1" }, { title: "Test Packet 2" }],
    },
    user: draft_user,
    guardian: Guardian.new(draft_user),
  )

if draft_result.success?
  draft_topic = draft_result[:main_topic]
  puts "  ✓ Created draft lottery: #{draft_topic.title} (id: #{draft_topic.id})"
else
  puts "  ✗ Failed to create draft lottery:"
  puts "    Result: #{draft_result.inspect}"
  if draft_result.respond_to?(:errors)
    puts "    Errors: #{draft_result.errors.full_messages}" if draft_result.errors.respond_to?(:full_messages)
  end
end

# Create ended lottery
ended_user = random_users[1]
puts ""
puts "Creating ended lottery for user: #{ended_user.username}"

ended_result =
  VzekcVerlosung::CreateLottery.call(
    params: {
      title: "TEST Ended Lottery #{Time.now.to_i}",
      duration_days: 7,
      category_id: category.id,
      packets: [{ title: "Test Packet A" }, { title: "Test Packet B" }],
    },
    user: ended_user,
    guardian: Guardian.new(ended_user),
  )

if ended_result.success?
  ended_topic = ended_result[:main_topic]
  # Activate the lottery
  ended_topic.custom_fields["lottery_state"] = "active"
  # Set end time to 1 day in the past so it's ended
  ended_topic.custom_fields["lottery_ends_at"] = 1.day.ago
  ended_topic.save_custom_fields
  ended_topic.reload

  puts "  ✓ Created and ended lottery: #{ended_topic.title} (id: #{ended_topic.id})"
  puts "    Ended at: #{ended_topic.lottery_ends_at}"
else
  puts "  ✗ Failed to create ended lottery:"
  puts "    Result: #{ended_result.inspect}"
  if ended_result.respond_to?(:errors)
    puts "    Errors: #{ended_result.errors.full_messages}" if ended_result.errors.respond_to?(:full_messages)
  end
end

puts ""
puts "=== Current State ==="

# Check draft lotteries
puts "Draft Lotteries:"
draft_topics =
  Topic
    .where(deleted_at: nil)
    .joins(:_custom_fields)
    .where(topic_custom_fields: { name: "lottery_state", value: "draft" })

if draft_topics.empty?
  puts "  No draft lotteries found"
else
  draft_topics.each { |t| puts "  - #{t.title} (user: #{t.user.username}, created: #{t.created_at})" }
end
puts ""

# Check ended active lotteries
puts "Active lotteries that have ended:"
ended_count = 0
Topic
  .where(deleted_at: nil)
  .joins(:_custom_fields)
  .where(topic_custom_fields: { name: "lottery_state", value: "active" })
  .each do |t|
    if t.lottery_ends_at && t.lottery_ends_at <= Time.zone.now && !t.lottery_drawn?
      puts "  - #{t.title} (ended: #{t.lottery_ends_at}, user: #{t.user.username})"
      ended_count += 1
    end
  end
puts "  No ended lotteries awaiting drawing" if ended_count.zero?
puts ""

# Run the jobs
puts "=== Running Draft Reminder Job ==="
begin
  Jobs::VzekcVerlosungDraftReminder.new.execute({})
  puts "✓ Draft reminder job completed successfully"
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(5)
end
puts ""

puts "=== Running Ended Reminder Job ==="
begin
  Jobs::VzekcVerlosungEndedReminder.new.execute({})
  puts "✓ Ended reminder job completed successfully"
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(5)
end
puts ""

puts "=== Check emails ==="
puts "Emails should now be visible in MailHog"
puts "You can also check:"
puts "  1. MailHog UI (usually http://localhost:8025)"
puts "  2. /admin/email/sent in your Discourse instance"
puts "  3. Look for email addresses: #{draft_user.email}, #{ended_user.email}"
