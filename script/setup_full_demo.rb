# frozen_string_literal: true

# Complete demo setup: Creates 4 lotteries with participants and publishes them
# Usage: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/setup_full_demo.rb [username]
#
# If no username is provided, randomly selects 4 different users from the "vereinsmitglied" group
# Ensures one packet per lottery has NO tickets for testing purposes

def get_random_vereinsmitglieder(count)
  group = Group.find_by(name: "vereinsmitglied")
  unless group
    puts "✗ Group 'vereinsmitglied' not found"
    exit 1
  end

  members = group.users.where("users.id > 0").to_a
  if members.count < count
    puts "⚠ Warning: Only #{members.count} members in vereinsmitglied group, need #{count}"
    return members
  end

  members.sample(count)
end

def get_participant_pool
  # Get users excluding system users and lottery owners
  User.where("id > 0").where.not(id: [-1, -2]).limit(50).to_a
end

def add_participants_to_lottery(topic, participant_pool, exclude_one_packet: true)
  packet_posts =
    Post
      .where(topic_id: topic.id)
      .order(:post_number)
      .select { |p| p.custom_fields["is_lottery_packet"] == true }

  puts "  Found #{packet_posts.count} packets"

  # Select one random packet to exclude from ticket sales
  excluded_packet = exclude_one_packet ? packet_posts.sample : nil
  if excluded_packet
    excluded_title = excluded_packet.raw.lines.first.to_s.gsub(/^#\s*/, "").strip
    puts "  ⚠ Excluding packet ##{excluded_packet.post_number} (#{excluded_title}) from ticket sales"
  end

  ticket_count = 0
  available_packets = excluded_packet ? packet_posts - [excluded_packet] : packet_posts

  # Each participant buys 1-5 random tickets
  participant_pool.shuffle.each do |user|
    num_packets = rand(1..5)
    selected_packets = available_packets.sample([num_packets, available_packets.length].min)

    selected_packets.each do |packet_post|
      ticket =
        VzekcVerlosung::LotteryTicket.find_or_create_by(post_id: packet_post.id, user_id: user.id)
      ticket_count += 1 if ticket.previously_new_record?
    end
  end

  puts "  ✓ Added #{ticket_count} tickets from #{participant_pool.count} participants"

  # Show summary
  packet_posts.each do |post|
    tickets = VzekcVerlosung::LotteryTicket.where(post_id: post.id)
    title = post.raw.lines.first.to_s.gsub(/^#\s*/, "").strip
    status = post == excluded_packet ? " [NO TICKETS]" : ""
    puts "    Packet ##{post.post_number}: #{tickets.count} tickets#{status}"
  end

  puts ""
end

def publish_lottery(topic)
  topic.custom_fields["lottery_state"] = "active"
  topic.custom_fields["lottery_ends_at"] = 2.weeks.from_now
  topic.save_custom_fields
  puts "  ✓ Published (ends: #{topic.custom_fields["lottery_ends_at"]})"
end

# ============================================================================
# Main Script
# ============================================================================

puts "=" * 80
puts "VZEKC VERLOSUNG - FULL DEMO SETUP"
puts "=" * 80
puts ""

username = ARGV[0]

if username
  users = [User.find_by(username: username)] * 4
  unless users.first
    puts "✗ User '#{username}' not found"
    exit 1
  end
  puts "Using specified user: #{users.first.username} (ID: #{users.first.id}) for all lotteries"
else
  users = get_random_vereinsmitglieder(4)
  puts "Selected 4 random lottery owners from vereinsmitglied group:"
  users.each_with_index do |user, i|
    puts "  #{i + 1}. #{user.username} (ID: #{user.id})"
  end
end
puts ""

# Get the lottery category
category_id = SiteSetting.vzekc_verlosung_category_id
if category_id.blank?
  puts "✗ vzekc_verlosung_category_id not configured in site settings"
  exit 1
end

# Get participant pool
participant_pool = get_participant_pool
puts "Participant pool: #{participant_pool.count} users"
puts ""

created_lotteries = []

# ============================================================================
# Lottery 1: Business Liquidation - Office Equipment
# ============================================================================
puts "=" * 80
puts "Creating Lottery 1: IT-Firma Liquidation..."
puts "=" * 80

description1 = <<~DESC
  ## Über diese Verlosung

  Diese Hardware stammt aus der Liquidation der Firma **TechnoData GmbH** aus Köln, die Ende der 1990er Jahre im Bereich CAD-Systeme und technischer Visualisierung tätig war. Der ehemalige Geschäftsführer hat uns die komplette Ausstattung seines Archivraums gespendet, nachdem er das Bürogebäude verkauft hat.

  Die Systeme wurden professionell gewartet und befinden sich größtenteils in sehr gutem Zustand. Einige Geräte wurden bis 2010 noch produktiv genutzt.

  ## Behaltene Systeme

  Für das Vereinsarchiv habe ich die komplette SGI Indigo² Workstation mit allen Handbüchern behalten, da diese ein wichtiges Zeugnis der professionellen 3D-Grafikgeschichte darstellt.

  ## Übergabe der Pakete

  **Abholung:** Die Pakete können in Köln-Ehrenfeld abgeholt werden (nach Terminvereinbarung). Ich bin auch bei den Classic Computing Treffen in Düsseldorf und Bonn dabei.

  **Versand:** Versand ist grundsätzlich möglich:
  - Versandkosten trägt der Gewinner
  - Gerne könnt ihr mir geeignetes Verpackungsmaterial zusenden
  - Schwere Systeme (Monitore, Desktop-Gehäuse) sollten möglichst abgeholt werden

  **Fristen:**
  - Bitte meldet euch innerhalb von 14 Tagen nach der Ziehung bei mir
  - Die Pakete können bis zu 8 Wochen bei mir gelagert werden
  - Schwere Monitore sollten möglichst zeitnah abgeholt werden (begrenzte Lagerfläche)
DESC

result1 =
  VzekcVerlosung::CreateLottery.call(
    user: users[0],
    guardian: Guardian.new(users[0]),
    params: {
      title: "Spende TechnoData GmbH – CAD-Workstations und Peripherie",
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: "IBM ThinkPad 600 mit Docking Station" },
        { title: "Compaq Deskpro EN mit 21\" CRT Monitor" },
        { title: "Sun Ultra 5 Workstation" },
        { title: "HP LaserJet 4 Plus Drucker" },
        { title: "3Com SuperStack Hub und Netzwerkkarten" },
        { title: "Iomega Zip 250 extern mit Disketten" },
        { title: "APC Back-UPS Pro 650" },
        { title: "Logitech Trackballs und Mäuse Sammlung" },
      ],
    },
  )

if result1.success?
  topic1 = result1.main_topic
  topic1.first_post.revise(users[0], raw: description1, edit_reason: "Initial description")
  puts "✓ Created: #{topic1.title} (ID: #{topic1.id})"

  add_participants_to_lottery(topic1, participant_pool, exclude_one_packet: true)
  publish_lottery(topic1)

  created_lotteries << topic1
else
  puts "✗ Failed to create lottery 1: #{result1.inspect}"
end
puts ""

# ============================================================================
# Lottery 2: Private Collector - Home Computer Collection
# ============================================================================
puts "=" * 80
puts "Creating Lottery 2: Sammler-Nachlass..."
puts "=" * 80

description2 = <<~DESC
  ## Über diese Verlosung

  Diese wunderbare Sammlung stammt von **Werner K.** aus Hannover, einem begeisterten Retro-Computing-Enthusiasten und langjährigen Vereinsmitglied, der aus gesundheitlichen Gründen seine Sammlung verkleinern muss. Werner hat über 30 Jahre lang Heimcomputer gesammelt und möchte nun sicherstellen, dass seine Schätze in gute Hände kommen.

  Werner war besonders an der Geschichte der 8-Bit-Ära interessiert und hat viele Systeme liebevoll restauriert und dokumentiert. Zu fast allen Geräten gibt es Originalverpackungen und Handbücher.

  ## Behaltene Systeme

  Werner behält seine beiden Amiga 3000 Systeme, da diese einen besonderen persönlichen Wert für ihn haben – damit hat er Anfang der 90er Jahre seine Diplomarbeit geschrieben.

  ## Übergabe der Pakete

  **Abholung:** Die Pakete können in Hannover-Linden abgeholt werden. Werner freut sich über Besuch von interessierten Retro-Fans (bitte Termin vereinbaren).

  **Versand:** Versand ist möglich und wird bevorzugt:
  - Versandkosten trägt der Gewinner
  - Alle Systeme werden mit Originalverpackung oder in geeigneten Kartons verschickt
  - Versicherter Versand via DHL Paket wird empfohlen

  **Fristen:**
  - Kontaktaufnahme innerhalb von 2 Wochen nach der Ziehung
  - Versand erfolgt innerhalb von 4 Wochen nach Kontaktaufnahme
DESC

result2 =
  VzekcVerlosung::CreateLottery.call(
    user: users[1],
    guardian: Guardian.new(users[1]),
    params: {
      title: "Sammlung Werner K. – Heimcomputer-Klassiker der 80er/90er",
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: "Commodore 64C mit 1541-II und Software" },
        { title: "Amiga 500 Plus mit RGB-Monitor" },
        { title: "Atari 800XL mit 1050 Diskettenlaufwerk" },
        { title: "Schneider CPC 6128 mit CTM644 Monitor" },
        { title: "Sinclair ZX Spectrum +2A Bundle" },
        { title: "MSX 2 Philips NMS 8250" },
        { title: "Commodore 128D mit 1571 Laufwerk" },
        { title: "Acorn Archimedes A3000" },
        { title: "Sharp X68000 mit Peripherie" },
        { title: "Vintage Joystick und Controller Sammlung" },
      ],
    },
  )

if result2.success?
  topic2 = result2.main_topic
  topic2.first_post.revise(users[1], raw: description2, edit_reason: "Initial description")
  puts "✓ Created: #{topic2.title} (ID: #{topic2.id})"

  add_participants_to_lottery(topic2, participant_pool, exclude_one_packet: true)
  publish_lottery(topic2)

  created_lotteries << topic2
else
  puts "✗ Failed to create lottery 2: #{result2.inspect}"
end
puts ""

# ============================================================================
# Lottery 3: Estate/Inheritance - IBM PC Collection
# ============================================================================
puts "=" * 80
puts "Creating Lottery 3: Nachlass eines PC-Pioniers..."
puts "=" * 80

description3 = <<~DESC
  ## Über diese Verlosung

  Diese Sammlung stammt aus dem Nachlass von **Dr. Karl-Heinz Schmidt** (1945-2024), der als einer der ersten deutschen PC-Händler in den 1980er Jahren eine wichtige Rolle bei der Verbreitung der IBM-kompatiblen PCs spielte. Seine Tochter hat uns kontaktiert und möchte die historisch wertvollen Systeme ihres Vaters an Menschen weitergeben, die sie zu schätzen wissen.

  Dr. Schmidt hat jedes System sorgfältig dokumentiert, inkl. Kaufbelegen, technischen Daten und handschriftlichen Notizen. Diese Dokumentation wird den jeweiligen Gewinnern mitgegeben – ein einzigartiger Einblick in die frühe PC-Geschichte Deutschlands.

  ## Behaltene Systeme

  Ein IBM 5150 Original PC (1981) mit allen Unterlagen bleibt in der Familie und wird dem Computermuseum in Paderborn als Leihgabe zur Verfügung gestellt.

  ## Übergabe der Pakete

  **Abholung:** Die Systeme befinden sich derzeit in Darmstadt bei der Familie. Abholung nach Terminvereinbarung möglich.

  **Versand:** Versand wird bevorzugt:
  - Versandkosten trägt der Gewinner
  - Professionelle Verpackung kann arrangiert werden
  - Versicherter Versand mit Sendungsverfolgung wird empfohlen
  - Internationale Gewinner willkommen

  **Fristen:**
  - Kontaktaufnahme innerhalb von 3 Wochen nach der Ziehung
  - Die Systeme können bis zu 3 Monate sicher gelagert werden
DESC

result3 =
  VzekcVerlosung::CreateLottery.call(
    user: users[2],
    guardian: Guardian.new(users[2]),
    params: {
      title: "Nachlass Dr. Schmidt – IBM PC Geschichte 1983-1995",
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: "IBM PC XT 5160 mit MDA Monitor" },
        { title: "IBM PC AT 5170 Model 339" },
        { title: "IBM PS/2 Model 80 mit VGA Monitor" },
        { title: "Compaq Portable II Luggable" },
        { title: "IBM ThinkPad 700C (1992)" },
        { title: "Vintage ISA Karten Sammlung" },
        { title: "5,25\" und 3,5\" Diskettenlaufwerke" },
        { title: "IBM Model M Tastaturen (3 Stück)" },
        { title: "Original IBM DOS und OS/2 Softwaresammlung" },
        { title: "PC-Peripherie Bundle (Mäuse, Kabel, Adapter)" },
        { title: "Historische Fachzeitschriften 1983-1990" },
      ],
    },
  )

if result3.success?
  topic3 = result3.main_topic
  topic3.first_post.revise(users[2], raw: description3, edit_reason: "Initial description")
  puts "✓ Created: #{topic3.title} (ID: #{topic3.id})"

  add_participants_to_lottery(topic3, participant_pool, exclude_one_packet: true)
  publish_lottery(topic3)

  created_lotteries << topic3
else
  puts "✗ Failed to create lottery 3: #{result3.inspect}"
end
puts ""

# ============================================================================
# Lottery 4: School Donation - Educational Hardware
# ============================================================================
puts "=" * 80
puts "Creating Lottery 4: Schulspende..."
puts "=" * 80

description4 = <<~DESC
  ## Über diese Verlosung

  Diese Hardware wurde uns vom **Heinrich-Hertz-Gymnasium** in München gespendet. Die Schule hat ihren Informatikraum komplett modernisiert und dabei die historische Sammlung aus dem Archiv aufgelöst. Die stellvertretende Schulleiterin, Frau Dr. Müller, hat sich sehr gefreut, dass die Systeme eine zweite Chance bei Enthusiasten bekommen.

  Diese Geräte wurden von 1990 bis 2005 im Informatikunterricht eingesetzt und haben Generationen von Schülern die ersten Programmiererfahrungen ermöglicht. Einige Systeme tragen noch die originalen Inventaraufkleber der Schule.

  ## Behaltene Systeme

  Für eine geplante Ausstellung "30 Jahre Informatikunterricht" wurden zwei Apple II GS Systeme und ein NeXT Cube zurückbehalten.

  ## Übergabe der Pakete

  **Abholung:** Die Pakete können in München-Schwabing abgeholt werden. Ich wohne in der Nähe der Schule und kann flexible Termine anbieten, auch abends und am Wochenende.

  **Versand:** Versand ist möglich:
  - Versandkosten trägt der Gewinner
  - Monitore sollten möglichst abgeholt werden
  - Kleinere Systeme und Peripherie verschicke ich gerne

  **Fristen:**
  - Kontaktaufnahme innerhalb von 14 Tagen
  - Abholung/Versand innerhalb von 6 Wochen
  - Nach 6 Wochen gehen nicht abgeholte Pakete an die Warteliste
DESC

result4 =
  VzekcVerlosung::CreateLottery.call(
    user: users[3],
    guardian: Guardian.new(users[3]),
    params: {
      title: "Spende Heinrich-Hertz-Gymnasium – Schul-IT der 90er Jahre",
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: "Apple Macintosh Classic II Bundle" },
        { title: "Apple PowerMac G3 Beige Desktop" },
        { title: "Acorn RiscPC 600 mit Monitor" },
        { title: "RM Nimbus PC-186 (UK Schulcomputer)" },
        { title: "BBC Micro Model B mit Acorn Monitor" },
        { title: "Apple IIe Europlus mit Disk II" },
        { title: "Atari ST 1040F mit SM124 Monitor" },
        { title: "Commodore PC-10 III (1987)" },
        { title: "LOGO Turtle Roboter mit Interface" },
        { title: "Bildungs-Software Sammlung (BBC, Apple, Atari)" },
        { title: "Overhead-Projektor Folien mit BASIC Code" },
        { title: "Original Informatik Lehrbücher 1985-2000" },
      ],
    },
  )

if result4.success?
  topic4 = result4.main_topic
  topic4.first_post.revise(users[3], raw: description4, edit_reason: "Initial description")
  puts "✓ Created: #{topic4.title} (ID: #{topic4.id})"

  add_participants_to_lottery(topic4, participant_pool, exclude_one_packet: true)
  publish_lottery(topic4)

  created_lotteries << topic4
else
  puts "✗ Failed to create lottery 4: #{result4.inspect}"
end
puts ""

# ============================================================================
# Summary
# ============================================================================
puts "=" * 80
puts "SETUP COMPLETE"
puts "=" * 80
puts ""
puts "Successfully created and published #{created_lotteries.count} demo lotteries:"
puts ""

created_lotteries.each_with_index do |topic, index|
  packet_count =
    Post.where(topic_id: topic.id).count { |p| p.custom_fields["is_lottery_packet"] == true }
  ticket_count = VzekcVerlosung::LotteryTicket.joins(:post).where(posts: { topic_id: topic.id }).count

  puts "#{index + 1}. #{topic.title}"
  puts "   Owner: #{topic.user.username}"
  puts "   Status: Active (ends #{topic.custom_fields["lottery_ends_at"]})"
  puts "   Packets: #{packet_count} (1 with no tickets)"
  puts "   Tickets: #{ticket_count}"
  puts "   URL: #{topic.url}"
  puts ""
end

puts "All lotteries are PUBLISHED and ACTIVE."
puts "You can now test the drawing feature by ending them early:"
puts ""
puts "  LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/test_lottery.rb end_early <topic_id>"
puts ""
