# frozen_string_literal: true

# Diagnostic script to check scheduled job status
# Run with: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/check_scheduled_jobs.rb

puts "=" * 80
puts "VZEKC VERLOSUNG SCHEDULED JOBS DIAGNOSTIC"
puts "=" * 80
puts ""

# Check if plugin is enabled
puts "1. SITE SETTINGS"
puts "-" * 80
puts "Plugin enabled: #{SiteSetting.vzekc_verlosung_enabled}"
puts "Reminder hour: #{SiteSetting.vzekc_verlosung_reminder_hour}"
puts "Draft reminders enabled: #{SiteSetting.vzekc_verlosung_draft_reminder_enabled}"
puts "Ended reminders enabled: #{SiteSetting.vzekc_verlosung_ended_reminder_enabled}"
puts "Ending tomorrow reminders enabled: #{SiteSetting.vzekc_verlosung_ending_tomorrow_reminder_enabled}"
puts ""

# Check current time
puts "2. TIME INFORMATION"
puts "-" * 80
puts "Current server time: #{Time.now}"
puts "Current zone time: #{Time.zone.now}"
puts "Current hour: #{Time.zone.now.hour}"
puts "Configured reminder hour: #{SiteSetting.vzekc_verlosung_reminder_hour || 7}"
puts "Next reminder at: #{Time.zone.now.beginning_of_day + (SiteSetting.vzekc_verlosung_reminder_hour || 7).hours}"
puts ""

# Check if jobs are registered
puts "3. JOB REGISTRATION"
puts "-" * 80

job_classes = [
  Jobs::VzekcVerlosungDraftReminder,
  Jobs::VzekcVerlosungEndedReminder,
  Jobs::VzekcVerlosungEndingTomorrowReminder,
]

job_classes.each do |job_class|
  puts "#{job_class.name}:"
  puts "  Scheduled: #{job_class.scheduled?}"
  puts "  Daily config: #{job_class.daily.inspect}"
  if job_class.daily && job_class.daily[:at]
    at_seconds = job_class.daily[:at].call
    at_hours = at_seconds / 3600.0
    puts "  Runs at: #{at_hours} hours (#{at_seconds} seconds since midnight)"
  end
  puts ""
end

# Check mini_scheduler status
puts "4. MINI_SCHEDULER STATUS"
puts "-" * 80

job_classes.each do |job_class|
  begin
    schedule_info = job_class.schedule_info
    puts "#{job_class.name}:"
    puts "  Valid: #{schedule_info.valid?}"
    puts "  Next run: #{schedule_info.next_run ? Time.at(schedule_info.next_run) : 'not scheduled'}"
    puts "  Prev run: #{schedule_info.prev_run ? Time.at(schedule_info.prev_run) : 'never'}"
    puts "  Prev result: #{schedule_info.prev_result}"
    puts "  Prev duration: #{schedule_info.prev_duration}s" if schedule_info.prev_duration
    puts ""
  rescue => e
    puts "  ERROR: #{e.message}"
    puts ""
  end
end

# Check for draft lotteries
puts "5. DRAFT LOTTERIES (should receive reminders)"
puts "-" * 80

draft_topics =
  Topic
    .where(deleted_at: nil)
    .joins(:_custom_fields)
    .where(topic_custom_fields: { name: "lottery_state", value: "draft" })

if draft_topics.any?
  draft_topics.each do |topic|
    puts "Topic ##{topic.id}: #{topic.title}"
    puts "  Creator: #{topic.user.username}"
    puts "  Created: #{topic.created_at}"
    puts ""
  end
else
  puts "No draft lotteries found"
  puts ""
end

# Check for ended lotteries
puts "6. ENDED LOTTERIES (should receive reminders)"
puts "-" * 80

ended_topics =
  Topic
    .where(deleted_at: nil)
    .joins(:_custom_fields)
    .where(topic_custom_fields: { name: "lottery_state", value: "active" })
    .select do |topic|
      topic.lottery_ends_at && topic.lottery_ends_at <= Time.zone.now && !topic.lottery_drawn?
    end

if ended_topics.any?
  ended_topics.each do |topic|
    puts "Topic ##{topic.id}: #{topic.title}"
    puts "  Creator: #{topic.user.username}"
    puts "  Ended: #{topic.lottery_ends_at}"
    puts "  Drawn: #{topic.lottery_drawn?}"
    puts ""
  end
else
  puts "No ended (undrawn) lotteries found"
  puts ""
end

# Check for lotteries ending tomorrow
puts "7. LOTTERIES ENDING TOMORROW (should receive reminders)"
puts "-" * 80

tomorrow_start = Time.zone.now.tomorrow.beginning_of_day
day_after_tomorrow = tomorrow_start + 1.day

tomorrow_topics =
  Topic
    .where(deleted_at: nil)
    .joins(:_custom_fields)
    .where(topic_custom_fields: { name: "lottery_state", value: "active" })
    .select do |topic|
      topic.lottery_ends_at && topic.lottery_ends_at >= tomorrow_start &&
        topic.lottery_ends_at < day_after_tomorrow
    end

if tomorrow_topics.any?
  tomorrow_topics.each do |topic|
    puts "Topic ##{topic.id}: #{topic.title}"
    puts "  Creator: #{topic.user.username}"
    puts "  Ends: #{topic.lottery_ends_at}"
    puts ""
  end
else
  puts "No lotteries ending tomorrow found"
  puts ""
end

# Check Sidekiq
puts "8. SIDEKIQ STATUS"
puts "-" * 80
begin
  require "sidekiq/api"
  stats = Sidekiq::Stats.new
  puts "Processed: #{stats.processed}"
  puts "Failed: #{stats.failed}"
  puts "Enqueued: #{stats.enqueued}"
  puts "Scheduled: #{stats.scheduled_size}"
  puts "Retries: #{stats.retry_size}"
  puts "Dead: #{stats.dead_size}"
  puts ""
rescue => e
  puts "ERROR: #{e.message}"
  puts ""
end

puts "=" * 80
puts "RECOMMENDATIONS"
puts "=" * 80
puts ""

if !SiteSetting.vzekc_verlosung_enabled
  puts "⚠️  Plugin is DISABLED. Enable it in site settings."
end

job_classes.each do |job_class|
  schedule_info = job_class.schedule_info rescue nil
  next unless schedule_info

  if !schedule_info.valid?
    puts "⚠️  #{job_class.name} schedule is INVALID. Run this to fix:"
    puts "   LOAD_PLUGINS=1 bundle exec rails runner \"#{job_class.name}.new.execute({})\""
  end
end

if Time.zone.now.hour != (SiteSetting.vzekc_verlosung_reminder_hour || 7)
  next_run = Time.zone.now.beginning_of_day + (SiteSetting.vzekc_verlosung_reminder_hour || 7).hours
  next_run += 1.day if next_run < Time.zone.now
  puts "ℹ️  Current hour (#{Time.zone.now.hour}) != reminder hour (#{SiteSetting.vzekc_verlosung_reminder_hour || 7})"
  puts "   Jobs will run at: #{next_run}"
end

puts ""
puts "To manually trigger a job for testing:"
puts "  LOAD_PLUGINS=1 bundle exec rails runner \"Jobs::VzekcVerlosungDraftReminder.new.execute({})\""
puts ""
puts "=" * 80
