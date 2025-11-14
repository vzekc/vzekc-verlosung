# frozen_string_literal: true

# Fix broken bidirectional links between donations and Erhaltungsberichte
#
# Due to a bug in plugin.rb (checking wrong opts key), the donation.erhaltungsbericht_topic_id
# was never set when Erhaltungsberichte were created. This script fixes existing data.
#
# Usage:
#   cd /Users/hans/Development/vzekc/discourse
#   LOAD_PLUGINS=1 bin/rails runner plugins/vzekc-verlosung/script/fix_erhaltungsbericht_links.rb

puts "Finding Erhaltungsbericht topics with donation_id custom field..."

erhaltungsberichte_category_id = SiteSetting.vzekc_verlosung_erhaltungsberichte_category_id

if erhaltungsberichte_category_id.blank?
  puts "ERROR: vzekc_verlosung_erhaltungsberichte_category_id site setting is not configured"
  exit 1
end

# Find all topics in Erhaltungsberichte category with donation_id custom field
erhaltungsbericht_topics =
  Topic
    .where(category_id: erhaltungsberichte_category_id)
    .joins(:_custom_fields)
    .where(topic_custom_fields: { name: "donation_id" })
    .includes(:_custom_fields)

puts "Found #{erhaltungsbericht_topics.count} Erhaltungsbericht topics"

fixed_count = 0
skipped_count = 0
error_count = 0

erhaltungsbericht_topics.each do |topic|
  donation_id = topic.custom_fields["donation_id"].to_i

  donation = VzekcVerlosung::Donation.find_by(id: donation_id)

  unless donation
    puts "  ERROR: Topic #{topic.id} references non-existent donation #{donation_id}"
    error_count += 1
    next
  end

  # Check if link is already set
  if donation.erhaltungsbericht_topic_id == topic.id
    puts "  SKIP: Donation #{donation.id} already linked to topic #{topic.id}"
    skipped_count += 1
    next
  end

  # Check if donation is already linked to a different Erhaltungsbericht
  if donation.erhaltungsbericht_topic_id.present?
    puts "  WARN: Donation #{donation.id} already has erhaltungsbericht_topic_id=#{donation.erhaltungsbericht_topic_id}, replacing with #{topic.id}"
  end

  # Set the link
  donation.update!(erhaltungsbericht_topic_id: topic.id)
  puts "  ✓ Fixed: Linked donation #{donation.id} to Erhaltungsbericht topic #{topic.id}"
  fixed_count += 1
end

puts "\nMigration complete!"
puts "  Fixed: #{fixed_count}"
puts "  Skipped (already correct): #{skipped_count}"
puts "  Errors: #{error_count}"
