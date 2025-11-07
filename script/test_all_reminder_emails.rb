# frozen_string_literal: true

# Comprehensive test script for all reminder emails
# Run with: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_all_reminder_emails.rb

puts "=== Testing All Reminder Emails ==="
puts ""

# Check and set reminder hour to current hour to ensure reminders run
current_hour = Time.zone.now.hour
original_reminder_hour = SiteSetting.vzekc_verlosung_reminder_hour
SiteSetting.vzekc_verlosung_reminder_hour = current_hour

puts "Settings:"
puts "  Plugin enabled: #{SiteSetting.vzekc_verlosung_enabled}"
puts "  Draft reminders enabled: #{SiteSetting.vzekc_verlosung_draft_reminder_enabled}"
puts "  Ended reminders enabled: #{SiteSetting.vzekc_verlosung_ended_reminder_enabled}"
puts "  Ending tomorrow reminders enabled: #{SiteSetting.vzekc_verlosung_ending_tomorrow_reminder_enabled}"
puts "  Uncollected reminders enabled: #{SiteSetting.respond_to?(:vzekc_verlosung_uncollected_reminder_enabled) ? SiteSetting.vzekc_verlosung_uncollected_reminder_enabled : 'N/A (setting not found)'}"
puts "  Erhaltungsbericht reminders enabled: #{SiteSetting.respond_to?(:vzekc_verlosung_erhaltungsbericht_reminder_enabled) ? SiteSetting.vzekc_verlosung_erhaltungsbericht_reminder_enabled : 'N/A (setting not found)'}"
puts "  Reminder hour: #{SiteSetting.vzekc_verlosung_reminder_hour} (set to current hour: #{current_hour})"
puts "  Lottery category: #{SiteSetting.vzekc_verlosung_category_id}"
puts ""

# Get users for testing
puts "=== Getting Test Users ==="
group = Group.find_by(name: "vereinsmitglieder")

if group
  test_users = group.users.order("RANDOM()").limit(5).to_a
  puts "Found #{test_users.size} users from 'Vereinsmitglieder' group"

  if test_users.size < 5
    puts "  WARNING: Only #{test_users.size} user(s) in group, using available users multiple times"
    while test_users.size < 5
      test_users << test_users[0]
    end
  end
else
  puts "  WARNING: 'Vereinsmitglieder' group not found, using admin users instead"
  test_users = User.where(admin: true).limit(5).to_a
  while test_users.size < 5
    test_users << test_users[0] if test_users.any?
  end
end

if test_users.empty?
  puts "  ERROR: No suitable users found. Cannot create test lotteries."
  exit 1
end

puts "Test users: #{test_users.map(&:username).join(', ')}"
puts ""

# Get lottery category
category_id = SiteSetting.vzekc_verlosung_category_id.to_i
category = Category.find_by(id: category_id)

unless category
  puts "Lottery category not found! Using default category..."
  category = Category.where(read_restricted: false).first
  puts "  Using category: #{category.name} (id: #{category.id})"
end

puts ""
puts "=== Creating Test Lotteries ==="
puts ""

# 1. DRAFT LOTTERY (for draft reminder)
draft_user = test_users[0]
puts "1. Creating DRAFT lottery for user: #{draft_user.username}"

draft_result = VzekcVerlosung::CreateLottery.call(
  params: {
    title: "TEST Draft Lottery #{Time.now.to_i}",
    duration_days: 7,
    category_id: category.id,
    packets: [
      { title: "Draft Packet 1" },
      { title: "Draft Packet 2" }
    ]
  },
  user: draft_user,
  guardian: Guardian.new(draft_user)
)

if draft_result.success?
  draft_topic = draft_result[:main_topic]
  puts "  ✓ Created draft lottery: #{draft_topic.title} (id: #{draft_topic.id})"
  puts "    State: #{draft_topic.lottery_state}"
else
  puts "  ✗ Failed to create draft lottery: #{draft_result.inspect}"
end

puts ""

# 2. ENDED LOTTERY (for ended reminder)
ended_user = test_users[1]
puts "2. Creating ENDED lottery (not drawn) for user: #{ended_user.username}"

ended_result = VzekcVerlosung::CreateLottery.call(
  params: {
    title: "TEST Ended Lottery #{Time.now.to_i}",
    duration_days: 7,
    category_id: category.id,
    packets: [
      { title: "Ended Packet A" },
      { title: "Ended Packet B" }
    ]
  },
  user: ended_user,
  guardian: Guardian.new(ended_user)
)

if ended_result.success?
  ended_topic = ended_result[:main_topic]
  # Activate and end the lottery
  ended_topic.custom_fields["lottery_state"] = "active"
  ended_topic.custom_fields["lottery_ends_at"] = 1.day.ago
  ended_topic.save_custom_fields
  ended_topic.reload

  puts "  ✓ Created ended lottery: #{ended_topic.title} (id: #{ended_topic.id})"
  puts "    State: #{ended_topic.lottery_state}, Ended: #{ended_topic.lottery_ends_at}"
else
  puts "  ✗ Failed to create ended lottery: #{ended_result.inspect}"
end

puts ""

# 3. ENDING TOMORROW LOTTERY (for ending tomorrow reminder)
tomorrow_user = test_users[2]
puts "3. Creating lottery ENDING TOMORROW for user: #{tomorrow_user.username}"

tomorrow_result = VzekcVerlosung::CreateLottery.call(
  params: {
    title: "TEST Ending Tomorrow Lottery #{Time.now.to_i}",
    duration_days: 7,
    category_id: category.id,
    packets: [
      { title: "Tomorrow Packet 1" },
      { title: "Tomorrow Packet 2" }
    ]
  },
  user: tomorrow_user,
  guardian: Guardian.new(tomorrow_user)
)

if tomorrow_result.success?
  tomorrow_topic = tomorrow_result[:main_topic]
  # Activate and set to end tomorrow
  tomorrow_topic.custom_fields["lottery_state"] = "active"
  tomorrow_topic.custom_fields["lottery_ends_at"] = 1.day.from_now
  tomorrow_topic.save_custom_fields
  tomorrow_topic.reload

  # Buy tickets from other users
  buyer = test_users[3]
  packet_posts = tomorrow_topic.posts.where.not(post_number: 1)
  if packet_posts.any?
    packet_post = packet_posts.first
    VzekcVerlosung::LotteryTicket.create!(
      post_id: packet_post.id,
      user_id: buyer.id
    )
    puts "  ✓ User #{buyer.username} bought ticket"
  end

  puts "  ✓ Created lottery ending tomorrow: #{tomorrow_topic.title} (id: #{tomorrow_topic.id})"
  puts "    State: #{tomorrow_topic.lottery_state}, Ends: #{tomorrow_topic.lottery_ends_at}"
else
  puts "  ✗ Failed to create ending tomorrow lottery: #{tomorrow_result.inspect}"
end

puts ""

# 4. UNCOLLECTED PACKET LOTTERY (for uncollected reminder)
uncollected_user = test_users[3]
winner_user = test_users[4]
puts "4. Creating lottery with UNCOLLECTED packet for winner: #{winner_user.username}"

uncollected_result = VzekcVerlosung::CreateLottery.call(
  params: {
    title: "TEST Uncollected Lottery #{Time.now.to_i}",
    duration_days: 7,
    category_id: category.id,
    packets: [
      { title: "Uncollected Packet" }
    ]
  },
  user: uncollected_user,
  guardian: Guardian.new(uncollected_user)
)

if uncollected_result.success?
  uncollected_topic = uncollected_result[:main_topic]
  # Activate, end, and draw winners
  uncollected_topic.custom_fields["lottery_state"] = "active"
  uncollected_topic.custom_fields["lottery_ends_at"] = 29.days.ago
  uncollected_topic.save_custom_fields
  uncollected_topic.reload

  # Buy ticket from winner
  packet_posts = uncollected_topic.posts.where.not(post_number: 1)
  if packet_posts.any?
    packet_post = packet_posts.first
    VzekcVerlosung::LotteryTicket.create!(
      post_id: packet_post.id,
      user_id: winner_user.id
    )

    # Draw lottery and assign winner - use 28 days (multiple of 7)
    uncollected_topic.custom_fields["lottery_state"] = "finished"
    uncollected_topic.custom_fields["lottery_drawn_at"] = 28.days.ago
    uncollected_topic.save_custom_fields

    packet_post.custom_fields["lottery_winner"] = winner_user.username
    packet_post.save_custom_fields
    packet_post.reload

    puts "  ✓ Created uncollected packet lottery: #{uncollected_topic.title} (id: #{uncollected_topic.id})"
    puts "    Winner: #{winner_user.username}, Won: 28 days ago (multiple of 7), Not collected"
  end
else
  puts "  ✗ Failed to create uncollected lottery: #{uncollected_result.inspect}"
end

puts ""

# 5. ERHALTUNGSBERICHT REMINDER (collected but no Erhaltungsbericht)
erb_owner = test_users[0]
erb_winner = test_users[1]
puts "5. Creating lottery with COLLECTED packet (no Erhaltungsbericht) for winner: #{erb_winner.username}"

erb_result = VzekcVerlosung::CreateLottery.call(
  params: {
    title: "TEST Erhaltungsbericht Lottery #{Time.now.to_i}",
    duration_days: 7,
    category_id: category.id,
    packets: [
      { title: "Collected Packet" }
    ]
  },
  user: erb_owner,
  guardian: Guardian.new(erb_owner)
)

if erb_result.success?
  erb_topic = erb_result[:main_topic]
  # Activate, end, and draw winners
  erb_topic.custom_fields["lottery_state"] = "active"
  erb_topic.custom_fields["lottery_ends_at"] = 85.days.ago
  erb_topic.save_custom_fields
  erb_topic.reload

  # Buy ticket from winner
  packet_posts = erb_topic.posts.where.not(post_number: 1)
  if packet_posts.any?
    packet_post = packet_posts.first
    VzekcVerlosung::LotteryTicket.create!(
      post_id: packet_post.id,
      user_id: erb_winner.id
    )

    # Draw lottery and assign winner
    erb_topic.custom_fields["lottery_state"] = "finished"
    erb_topic.custom_fields["lottery_drawn_at"] = 84.days.ago
    erb_topic.save_custom_fields

    # Use 56 days (multiple of 7) for collection date
    packet_post.custom_fields["lottery_winner"] = erb_winner.username
    packet_post.custom_fields["packet_collected_at"] = 56.days.ago
    packet_post.save_custom_fields
    packet_post.reload

    puts "  ✓ Created Erhaltungsbericht reminder lottery: #{erb_topic.title} (id: #{erb_topic.id})"
    puts "    Winner: #{erb_winner.username}, Collected: 56 days ago (multiple of 7), No Erhaltungsbericht"
  end
else
  puts "  ✗ Failed to create Erhaltungsbericht lottery: #{erb_result.inspect}"
end

puts ""
puts "=== Running Reminder Jobs ==="
puts ""

# 1. Draft Reminder
puts "1. Running Draft Reminder Job..."
begin
  Jobs::VzekcVerlosungDraftReminder.new.execute({})
  puts "   ✓ Draft reminder job completed"
rescue StandardError => e
  puts "   ✗ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end
puts ""

# 2. Ended Reminder
puts "2. Running Ended Reminder Job..."
begin
  Jobs::VzekcVerlosungEndedReminder.new.execute({})
  puts "   ✓ Ended reminder job completed"
rescue StandardError => e
  puts "   ✗ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end
puts ""

# 3. Ending Tomorrow Reminder
puts "3. Running Ending Tomorrow Reminder Job..."
begin
  Jobs::VzekcVerlosungEndingTomorrowReminder.new.execute({})
  puts "   ✓ Ending tomorrow reminder job completed"
rescue StandardError => e
  puts "   ✗ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end
puts ""

# 4. Uncollected Reminder
puts "4. Running Uncollected Reminder Job..."
begin
  Jobs::VzekcVerlosungUncollectedReminder.new.execute({})
  puts "   ✓ Uncollected reminder job completed"
rescue StandardError => e
  puts "   ✗ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end
puts ""

# 5. Erhaltungsbericht Reminder
puts "5. Running Erhaltungsbericht Reminder Job..."
begin
  Jobs::VzekcVerlosungErhaltungsberichtReminder.new.execute({})
  puts "   ✓ Erhaltungsbericht reminder job completed"
rescue StandardError => e
  puts "   ✗ Error: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
end
puts ""

puts "=== Summary ==="
puts ""

# Restore original reminder hour
SiteSetting.vzekc_verlosung_reminder_hour = original_reminder_hour
puts "Restored reminder hour to: #{original_reminder_hour}"
puts ""

puts "All reminder jobs have been executed!"
puts ""
puts "Check emails at:"
puts "  1. MailHog UI: http://localhost:8025"
puts "  2. Discourse Admin: http://127.0.0.1:4200/admin/email/sent"
puts ""
puts "Expected emails:"
puts "  1. Draft reminder → #{draft_user.email}"
puts "  2. Ended reminder → #{ended_user.email}"
puts "  3. Ending tomorrow reminder → #{buyer&.email || 'N/A'}"
puts "  4. Uncollected reminder → #{winner_user.email}"
puts "  5. Erhaltungsbericht reminder → #{erb_winner.email}"
puts ""
puts "Note: Reminder jobs only send emails if all conditions are met:"
puts "  - Draft: Any draft lottery found"
puts "  - Ended: Active lottery that has ended but not drawn"
puts "  - Ending tomorrow: Active lottery ending in ~24 hours"
puts "  - Uncollected: Won packet, days since drawn = multiple of 7 (7, 14, 21, 28...)"
puts "  - Erhaltungsbericht: Collected packet, days since collected = multiple of 7 (7, 14, 21, 56...)"
puts ""
