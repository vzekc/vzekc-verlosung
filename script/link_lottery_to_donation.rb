# frozen_string_literal: true

# Script to link an existing lottery to a donation
#
# Usage (from Discourse root):
#   LOAD_PLUGINS=1 rails runner plugins/vzekc-verlosung/script/link_lottery_to_donation.rb LOTTERY_ID DONATION_ID
#
# Example:
#   LOAD_PLUGINS=1 rails runner plugins/vzekc-verlosung/script/link_lottery_to_donation.rb 32 8

lottery_id = ARGV[0]&.to_i
donation_id = ARGV[1]&.to_i

if lottery_id.nil? || lottery_id.zero? || donation_id.nil? || donation_id.zero?
  puts "Usage: rails runner script/link_lottery_to_donation.rb LOTTERY_ID DONATION_ID"
  puts ""
  puts "To find unlinked donations and their potential lotteries, run:"
  puts "  rails runner script/link_lottery_to_donation.rb --list"
  exit 1
end

if ARGV[0] == "--list"
  puts "Donations needing action (no linked lottery or Erhaltungsbericht):"
  puts ""

  VzekcVerlosung::Donation
    .where(state: %w[picked_up closed])
    .includes(:topic, :lottery, pickup_offers: :user)
    .each do |d|
      next if d.pickup_action_completed?

      picker = d.pickup_offers.find { |o| o.state.in?(%w[assigned picked_up]) }&.user
      puts "Donation ID: #{d.id}"
      puts "  Topic: #{d.topic&.title || '(no topic)'}"
      puts "  Picker: #{picker&.username || '(unknown)'}"
      puts ""

      if picker
        lotteries = VzekcVerlosung::Lottery.joins(:topic).where(topics: { user_id: picker.id }, donation_id: nil)
        if lotteries.any?
          puts "  Potential lotteries by #{picker.username}:"
          lotteries.each do |l|
            puts "    - Lottery #{l.id}: #{l.topic&.title} (#{l.state})"
          end
        end
      end
      puts ""
    end
  exit 0
end

lottery = VzekcVerlosung::Lottery.find_by(id: lottery_id)
donation = VzekcVerlosung::Donation.find_by(id: donation_id)

if lottery.nil?
  puts "Error: Lottery #{lottery_id} not found"
  exit 1
end

if donation.nil?
  puts "Error: Donation #{donation_id} not found"
  exit 1
end

if lottery.donation_id.present?
  puts "Error: Lottery #{lottery_id} is already linked to donation #{lottery.donation_id}"
  exit 1
end

puts "Linking lottery to donation..."
puts ""
puts "Lottery: #{lottery.id} - #{lottery.topic&.title}"
puts "Donation: #{donation.id} - #{donation.topic&.title}"
puts ""

lottery.update!(donation_id: donation.id)

puts "Done! Donation pickup_action_completed? is now: #{donation.reload.pickup_action_completed?}"
