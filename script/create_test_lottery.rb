# frozen_string_literal: true

# Create a test lottery with retro computer packets
# Usage: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/create_test_lottery.rb <username>

username = ARGV[0] || "hans"

user = User.find_by(username: username)
unless user
  puts "✗ User '#{username}' not found"
  exit 1
end

puts "User found: #{user.username} (ID: #{user.id})"

# Get the lottery category
category_id = SiteSetting.vzekc_verlosung_category_id
puts "Category ID: #{category_id}"

if category_id.blank?
  puts "✗ vzekc_verlosung_category_id not configured in site settings"
  exit 1
end

# Create the lottery with 12 retro computer packets
result =
  VzekcVerlosung::CreateLottery.call(
    user: user,
    guardian: Guardian.new(user),
    params: {
      title: "Retro-Hardware Verlosung #{Time.zone.today.strftime("%B %Y")}",
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: "Commodore 64 mit Datasette" },
        { title: "Amiga 500 Bundle mit Maus und Joystick" },
        { title: "Atari ST 1040 mit Monitor" },
        { title: "Apple IIe Komplettsystem" },
        { title: "ZX Spectrum +2 mit Spielen" },
        { title: "IBM PS/2 Model 30" },
        { title: "Schneider CPC 464 mit Grünmonitor" },
        { title: "Amstrad PCW 8256 Textverarbeitung" },
        { title: "Sinclair QL mit Microdrive" },
        { title: "Atari 2600 Konsole mit Spielesammlung" },
        { title: "Commodore Plus/4 Bundle" },
        { title: "Vintage PC-Tastatur und Maus Set" },
      ],
    },
  )

if result.success?
  topic = result.main_topic
  puts ""
  puts "✓ Lottery created successfully!"
  puts "  Topic ID: #{topic.id}"
  puts "  Topic Title: #{topic.title}"
  puts "  Topic URL: #{topic.url}"
  puts ""
  puts "Next steps:"
  puts "  1. Edit the lottery description at #{topic.url}"
  puts "  2. Add test participants: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/add_test_participants.rb #{topic.id}"
  puts "  3. Publish the lottery (via UI or script)"
else
  puts ""
  puts "✗ Failed to create lottery"
  puts "  Error: #{result.inspect}"
  exit 1
end
