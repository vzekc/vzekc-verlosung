# Troubleshooting Guide - Vzekc Verlosung Scheduled Jobs

## Quick Diagnostic

Run this script on your production server to diagnose scheduled job issues:

```bash
cd /var/www/discourse  # or your Discourse installation directory
LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/check_scheduled_jobs.rb
```

## Common Issues

### 1. Jobs Not Running At All

**Symptoms**: No reminders are being sent

**Causes**:
- Plugin not enabled in site settings
- mini_scheduler not running
- Sidekiq not running

**Solutions**:

1. Check if plugin is enabled:
   ```bash
   # In Rails console
   LOAD_PLUGINS=1 bundle exec rails c
   > SiteSetting.vzekc_verlosung_enabled
   # Should return true
   ```

2. Check Sidekiq is running:
   ```bash
   # Check Sidekiq process
   ps aux | grep sidekiq

   # Or check via Discourse admin panel
   # Visit: https://your-forum.com/sidekiq/busy
   ```

3. Check mini_scheduler is started:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails c
   > MiniScheduler::Manager.current
   # Should return hash of managers, not nil
   ```

### 2. Jobs Not Running at Configured Time

**Symptoms**: Jobs run but at wrong time, or not at expected hour

**Causes**:
- Server timezone different from expected
- Job schedule needs to be refreshed after deployment
- Configuration cached from before deployment

**Solutions**:

1. Check server timezone:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "puts Time.zone.name; puts Time.zone.now"
   ```

2. Verify configured hour:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "puts SiteSetting.vzekc_verlosung_reminder_hour"
   # Default is 7 (7 AM)
   ```

3. Force schedule refresh:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "
   Jobs::VzekcVerlosungDraftReminder.schedule_info.schedule!
   Jobs::VzekcVerlosungEndedReminder.schedule_info.schedule!
   Jobs::VzekcVerlosungEndingTomorrowReminder.schedule_info.schedule!
   puts 'Schedules refreshed'
   "
   ```

### 3. Jobs Running But Not Sending Emails

**Symptoms**: Jobs execute but no emails are received

**Causes**:
- No eligible lotteries (no drafts, no ended lotteries)
- Email delivery not configured
- Email settings disabled

**Solutions**:

1. Check if there are eligible lotteries:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/check_scheduled_jobs.rb | grep -A 5 "DRAFT LOTTERIES"
   ```

2. Check email is enabled:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "puts SiteSetting.disable_emails"
   # Should be 'no' for emails to work
   ```

3. Test email delivery:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "
   user = User.find_by(username: 'your_username')
   topic = Topic.joins(:_custom_fields).where(topic_custom_fields: { name: 'lottery_state', value: 'draft' }).first
   message = VzekcVerlosungMailer.draft_reminder(user, topic)
   Email::Sender.new(message, :vzekc_verlosung_draft_reminder).send
   puts 'Test email sent'
   "
   ```

### 4. Jobs Failing Silently

**Symptoms**: Schedule shows jobs should run but they don't execute

**Causes**:
- Job raising exceptions
- Redis connection issues
- Database connection issues

**Solutions**:

1. Check Sidekiq for failed jobs:
   - Visit: `https://your-forum.com/sidekiq/retries`
   - Look for vzekc_verlosung jobs

2. Check logs for errors:
   ```bash
   tail -f log/production.log | grep -i "vzekc_verlosung"
   ```

3. Manually run job to see errors:
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "
   begin
     Jobs::VzekcVerlosungDraftReminder.new.execute({})
     puts 'Job executed successfully'
   rescue => e
     puts 'ERROR: ' + e.message
     puts e.backtrace.join(\"\n\")
   end
   "
   ```

## Manual Testing

### Manually Trigger a Reminder Job

```bash
# Draft reminder
LOAD_PLUGINS=1 bundle exec rails runner "Jobs::VzekcVerlosungDraftReminder.new.execute({})"

# Ended reminder
LOAD_PLUGINS=1 bundle exec rails runner "Jobs::VzekcVerlosungEndedReminder.new.execute({})"

# Ending tomorrow reminder
LOAD_PLUGINS=1 bundle exec rails runner "Jobs::VzekcVerlosungEndingTomorrowReminder.new.execute({})"
```

### Check Next Scheduled Run Time

```bash
LOAD_PLUGINS=1 bundle exec rails runner "
puts 'Draft Reminder: ' + (Jobs::VzekcVerlosungDraftReminder.schedule_info.next_run ? Time.at(Jobs::VzekcVerlosungDraftReminder.schedule_info.next_run).to_s : 'Not scheduled')
puts 'Ended Reminder: ' + (Jobs::VzekcVerlosungEndedReminder.schedule_info.next_run ? Time.at(Jobs::VzekcVerlosungEndedReminder.schedule_info.next_run).to_s : 'Not scheduled')
puts 'Ending Tomorrow Reminder: ' + (Jobs::VzekcVerlosungEndingTomorrowReminder.schedule_info.next_run ? Time.at(Jobs::VzekcVerlosungEndingTomorrowReminder.schedule_info.next_run).to_s : 'Not scheduled')
"
```

### Force Schedule All Jobs to Run Now (Testing Only)

```bash
LOAD_PLUGINS=1 bundle exec rails runner "
# WARNING: This will modify the schedule temporarily
info = Jobs::VzekcVerlosungDraftReminder.schedule_info
info.next_run = Time.now.to_i
info.write!
puts 'Draft reminder scheduled to run immediately'
puts 'Wait a few minutes and check if it runs'
"
```

## Configuration Reference

### Site Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `vzekc_verlosung_enabled` | false | Master switch for plugin |
| `vzekc_verlosung_reminder_hour` | 7 | Hour of day (0-23) when reminders are sent |
| `vzekc_verlosung_draft_reminder_enabled` | true | Send draft lottery reminders |
| `vzekc_verlosung_ended_reminder_enabled` | true | Send ended lottery reminders |
| `vzekc_verlosung_ending_tomorrow_reminder_enabled` | true | Send ending tomorrow reminders |

### Checking Settings

```bash
LOAD_PLUGINS=1 bundle exec rails runner "
puts 'Plugin enabled: ' + SiteSetting.vzekc_verlosung_enabled.to_s
puts 'Reminder hour: ' + SiteSetting.vzekc_verlosung_reminder_hour.to_s
puts 'Draft reminders: ' + SiteSetting.vzekc_verlosung_draft_reminder_enabled.to_s
puts 'Ended reminders: ' + SiteSetting.vzekc_verlosung_ended_reminder_enabled.to_s
puts 'Ending tomorrow reminders: ' + SiteSetting.vzekc_verlosung_ending_tomorrow_reminder_enabled.to_s
"
```

## After Deployment Checklist

When you deploy the plugin or update it:

1. ✅ Restart Discourse (or at least Sidekiq)
   ```bash
   sv restart unicorn
   sv restart sidekiq
   ```

2. ✅ Verify plugin loaded
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "puts 'Plugin loaded' if defined?(VzekcVerlosung)"
   ```

3. ✅ Check settings are enabled
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/check_scheduled_jobs.rb | head -20
   ```

4. ✅ Verify schedules are valid
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/check_scheduled_jobs.rb | grep -A 5 "MINI_SCHEDULER STATUS"
   ```

5. ✅ Manually test one job
   ```bash
   LOAD_PLUGINS=1 bundle exec rails runner "Jobs::VzekcVerlosungDraftReminder.new.execute({}); puts 'Success'"
   ```

## Getting Help

If you're still having issues:

1. Run the diagnostic script and save the output
2. Check `/logs/production.log` for errors
3. Check Sidekiq dashboard at `https://your-forum.com/sidekiq`
4. Note your Discourse version and Ruby version
5. Create an issue with all the above information
