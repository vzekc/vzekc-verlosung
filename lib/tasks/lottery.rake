# frozen_string_literal: true

desc "Fix lottery winners from results JSON (for lotteries affected by duplicate title bug)"
task "lottery:fix_winners", [:topic_id] => :environment do |_, args|
  topic_id = args[:topic_id]

  if topic_id.blank?
    puts "Usage: rake lottery:fix_winners[TOPIC_ID]"
    puts "Example: rake lottery:fix_winners[177]"
    exit 1
  end

  lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic_id)

  if lottery.nil?
    puts "Error: No lottery found for topic #{topic_id}"
    exit 1
  end

  results = lottery.results

  if results.nil?
    puts "Error: Lottery has no results (not yet drawn?)"
    exit 1
  end

  packets_data = results["packets"]
  drawings = results["drawings"]

  if packets_data.nil? || drawings.nil?
    puts "Error: Results JSON missing 'packets' or 'drawings' array"
    puts "This lottery may have been drawn with an older version."
    exit 1
  end

  puts "Lottery: #{lottery.topic.title}"
  puts "Found #{drawings.length} drawings and #{packets_data.length} packets in results JSON"
  puts ""

  changes = []

  drawings.each_with_index do |drawing, index|
    packet_data = packets_data[index]

    unless packet_data
      puts "Warning: No packet data at index #{index}, skipping"
      next
    end

    post_id = packet_data["id"]
    winner_username = drawing["winner"]
    packet_title = drawing["text"]

    lottery_packet = lottery.lottery_packets.find { |p| p.post_id == post_id }

    unless lottery_packet
      puts "Warning: No lottery packet found for post_id #{post_id}, skipping"
      next
    end

    current_winner = lottery_packet.winner&.username
    expected_winner = winner_username

    if current_winner == expected_winner
      puts "OK: Packet ##{lottery_packet.ordinal} '#{packet_title}' -> #{expected_winner || "(no winner)"}"
    else
      puts "MISMATCH: Packet ##{lottery_packet.ordinal} '#{packet_title}'"
      puts "  Current:  #{current_winner || "(none)"}"
      puts "  Expected: #{expected_winner || "(no winner)"}"

      changes << {
        packet: lottery_packet,
        packet_title: packet_title,
        current_winner: current_winner,
        expected_winner: expected_winner,
      }
    end
  end

  puts ""

  if changes.empty?
    puts "All winners are correct. No changes needed."
    exit 0
  end

  puts "Found #{changes.length} packet(s) with incorrect winners."
  print "Do you want to fix them? [y/N]: "
  answer = $stdin.gets.chomp.downcase

  unless answer == "y"
    puts "Aborted."
    exit 0
  end

  puts ""
  puts "Fixing winners..."

  changes.each do |change|
    packet = change[:packet]
    expected_winner = change[:expected_winner]

    if expected_winner.nil?
      # No winner expected, clear the winner
      packet.update!(winner_user_id: nil, won_at: nil)
      puts "Cleared winner for packet ##{packet.ordinal} '#{change[:packet_title]}'"
    else
      winner_user = User.find_by(username: expected_winner)

      if winner_user.nil?
        puts "Error: User '#{expected_winner}' not found, skipping packet ##{packet.ordinal}"
        next
      end

      packet.update!(winner_user_id: winner_user.id, won_at: lottery.drawn_at)
      puts "Set winner for packet ##{packet.ordinal} '#{change[:packet_title]}' -> #{expected_winner}"
    end
  end

  puts ""
  puts "Done!"
end
