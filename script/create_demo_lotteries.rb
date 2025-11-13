# frozen_string_literal: true

# Create four realistic demo lotteries with different sources and packet types
# Usage: LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/create_demo_lotteries.rb [username]
#
# If no username is provided, randomly selects 4 different users from the "vereinsmitglied" group

def random_vereinsmitglieder(count)
  group = Group.find_by(name: 'vereinsmitglied') ||
          (puts("✗ Group 'vereinsmitglied' not found") && exit(1))
  members = group.users.where('users.id > 0').to_a
  if members.count < count
    puts "⚠ Warning: Only #{members.count} members in vereinsmitglied group, need #{count}"
    members
  else
    members.sample(count)
  end
end

username = ARGV[0]

if username
  users = [User.find_by(username: username)] * 4
  unless users.first
    puts "✗ User '#{username}' not found"
    exit 1
  end
  puts "Using specified user: #{users.first.username} (ID: #{users.first.id}) for all lotteries"
else
  users = random_vereinsmitglieder(4)
  puts 'Selected 4 random users from vereinsmitglied group:'
  users.each_with_index do |user, i|
    puts "  #{i + 1}. #{user.username} (ID: #{user.id})"
  end
  puts ''
end

# Get the lottery category
category_id = SiteSetting.vzekc_verlosung_category_id
puts "Category ID: #{category_id}"

if category_id.blank?
  puts '✗ vzekc_verlosung_category_id not configured in site settings'
  exit 1
end

# Get the description template
SiteSetting.vzekc_verlosung_description_template

created_lotteries = []

# ============================================================================
# Lottery 1: Business Liquidation - Office Equipment
# ============================================================================
puts "\n#{'=' * 80}"
puts 'Creating Lottery 1: IT-Firma Liquidation...'
puts '=' * 80

description1 = <<~DESC
  ## Über diese Verlosung

  Diese Hardware stammt aus der Liquidation der Firma **TechnoData GmbH** aus Köln, die Ende der 1990er Jahre im Bereich CAD-Systeme und technischer Visualisierung tätig war. Der ehemalige Geschäftsführer hat uns die komplette Ausstattung seines Archivraums gespendet, nachdem er das Bürogebäude verkauft hat.

  Die Systeme wurden professionell gewartet und befinden sich größtenteils in sehr gutem Zustand. Einige Geräte wurden bis 2010 noch produktiv genutzt.

  ## Behaltenes System

  Aus der Spende habe ich eine SGI Indigo² Workstation für mich behalten, da ich schon lange nach so einem System suche und es perfekt in meine Sammlung passt.

  ## Übergabe der Pakete

  Ich habe alle Systeme in Köln abgeholt.

  **Abholung:** Die Pakete können in 50823 Köln-Ehrenfeld abgeholt werden (nach Terminvereinbarung). Ich bin auch regelmäßig bei den Classic Computing Treffen in Düsseldorf und Bonn – dort können Pakete ebenfalls übergeben werden.

  **Versand:** Versand ist grundsätzlich möglich:
  - Versandkosten trägt der Gewinner
  - Gerne könnt ihr mir geeignetes Verpackungsmaterial zusenden
  - Schwere Systeme (Monitore, Desktop-Gehäuse) sollten möglichst abgeholt werden

  **Fristen:**
  - Versand innerhalb von 2 Wochen nach Kontaktaufnahme
  - Abholung innerhalb von 8 Wochen nach der Ziehung
  - Nicht abgeholte Pakete kommen in eine neue Verlosung
DESC

result1 =
  VzekcVerlosung::CreateLottery.call(
    user: users[0],
    guardian: Guardian.new(users[0]),
    params: {
      title: 'Spende TechnoData GmbH – CAD-Workstations und Peripherie',
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: 'Sun Ultra 10 Creator3D Workstation' },
        { title: 'HP Visualize C3000 Workstation mit 21" Monitor' },
        { title: 'Silicon Graphics O2 Workstation' },
        { title: 'Intergraph TDZ-2000 GL1 Workstation' },
        { title: 'HP DesignJet 350C Plotter (A1)' },
        { title: '3Dconnexion SpaceMouse und Grafiktablett Bundle' },
        { title: '21" und 24" CRT Monitore (Sony GDM, NEC MultiSync)' },
        { title: 'SCSI-Festplatten und DAT-Tape Backup System' }
      ]
    }
  )

if result1.success?
  topic1 = result1.main_topic
  # Update the description
  topic1.first_post.revise(users[0], raw: description1, edit_reason: 'Initial description')
  created_lotteries << topic1
  puts "✓ Lottery 1 created: #{topic1.title} (ID: #{topic1.id})"
else
  puts "✗ Failed to create lottery 1: #{result1.inspect}"
end

# ============================================================================
# Lottery 2: Private Collector - Home Computer Collection
# ============================================================================
puts "\n#{'=' * 80}"
puts 'Creating Lottery 2: Sammler-Nachlass...'
puts '=' * 80

description2 = <<~DESC
  ## Über diese Verlosung

  Diese wunderbare Sammlung haben wir von **Werner K.** aus Hannover erhalten, einem begeisterten Retro-Computing-Enthusiasten, der aus gesundheitlichen Gründen seine Sammlung verkleinern muss. Werner hat über 30 Jahre lang Heimcomputer gesammelt und freut sich, dass seine Schätze in gute Hände kommen.

  Werner war besonders an der Geschichte der 8-Bit-Ära interessiert und hat viele Systeme liebevoll restauriert und dokumentiert. Zu fast allen Geräten gibt es Originalverpackungen und Handbücher.

  ## Behaltenes System

  Aus der Spende habe ich einen Commodore Amiga 1200 für mich behalten – ein System, das ich schon seit meiner Jugend haben wollte.

  ## Übergabe der Pakete

  Ich habe alle Systeme bei Werner in Hannover abgeholt.

  **Abholung:** Die Pakete können in 70173 Stuttgart (Stuttgart-Mitte) abgeholt werden (nach Terminvereinbarung).

  **Versand:** Versand ist möglich und wird bevorzugt:
  - Versandkosten trägt der Gewinner
  - Alle Systeme können sicher verpackt werden (teilweise mit Originalverpackung)
  - Versicherter Versand via DHL Paket wird empfohlen

  **Fristen:**
  - Versand innerhalb von 1 Woche nach Kontaktaufnahme
  - Abholung innerhalb von 6 Wochen nach der Ziehung
  - Nicht abgeholte Pakete behalte ich
DESC

result2 =
  VzekcVerlosung::CreateLottery.call(
    user: users[1],
    guardian: Guardian.new(users[1]),
    params: {
      title: 'Sammlung Werner K. – Heimcomputer-Klassiker der 80er/90er',
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: 'Commodore 64C mit 1541-II und Software' },
        { title: 'Amiga 500 Plus mit RGB-Monitor' },
        { title: 'Atari 800XL mit 1050 Diskettenlaufwerk' },
        { title: 'Schneider CPC 6128 mit CTM644 Monitor' },
        { title: 'Sinclair ZX Spectrum +2A Bundle' },
        { title: 'MSX 2 Philips NMS 8250' },
        { title: 'Commodore 128D mit 1571 Laufwerk' },
        { title: 'Acorn Archimedes A3000' },
        { title: 'Sharp X68000 mit Peripherie' },
        { title: 'Vintage Joystick und Controller Sammlung' }
      ]
    }
  )

if result2.success?
  topic2 = result2.main_topic
  topic2.first_post.revise(users[1], raw: description2, edit_reason: 'Initial description')
  created_lotteries << topic2
  puts "✓ Lottery 2 created: #{topic2.title} (ID: #{topic2.id})"
else
  puts "✗ Failed to create lottery 2: #{result2.inspect}"
end

# ============================================================================
# Lottery 3: Estate/Inheritance - IBM PC Collection
# ============================================================================
puts "\n#{'=' * 80}"
puts 'Creating Lottery 3: Nachlass eines PC-Pioniers...'
puts '=' * 80

description3 = <<~DESC
  ## Über diese Verlosung

  Diese Sammlung haben wir aus dem Nachlass von **Dr. Karl-Heinz Schmidt** (1945-2024) erhalten, der als einer der ersten deutschen PC-Händler in den 1980er Jahren eine wichtige Rolle bei der Verbreitung der IBM-kompatiblen PCs spielte. Seine Tochter hat uns kontaktiert und wollte die historisch wertvollen Systeme ihres Vaters an Menschen weitergeben, die sie zu schätzen wissen.

  Dr. Schmidt hat jedes System sorgfältig dokumentiert, inkl. Kaufbelegen, technischen Daten und handschriftlichen Notizen. Diese Dokumentation wird den jeweiligen Gewinnern mitgegeben – ein einzigartiger Einblick in die frühe PC-Geschichte Deutschlands.

  ## Behaltenes System

  Aus der Spende habe ich einen IBM PC AT 5170 für mich behalten – dieses System hat mich schon immer fasziniert und passt perfekt in meine PC-Sammlung.

  ## Übergabe der Pakete

  Ich habe alle Systeme bei der Familie in Darmstadt abgeholt.

  **Abholung:** Die Pakete können in 60311 Frankfurt am Main (Innenstadt) abgeholt werden (nach Terminvereinbarung). Ich bin auch oft auf dem Rhein-Main Classic Computing Stammtisch.

  **Versand:** Versand wird bevorzugt:
  - Versandkosten trägt der Gewinner
  - Systeme können gut verpackt werden
  - Versicherter Versand mit Sendungsverfolgung wird empfohlen
  - Internationale Gewinner willkommen

  **Fristen:**
  - Versand innerhalb von 2 Wochen nach Kontaktaufnahme
  - Abholung innerhalb von 12 Wochen nach der Ziehung
  - Nicht abgeholte Pakete kommen in eine neue Verlosung
DESC

result3 =
  VzekcVerlosung::CreateLottery.call(
    user: users[2],
    guardian: Guardian.new(users[2]),
    params: {
      title: 'Nachlass Dr. Schmidt – IBM PC Geschichte 1983-1995',
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: 'IBM PC XT 5160 mit MDA Monitor' },
        { title: 'IBM PC AT 5170 Model 339' },
        { title: 'IBM PS/2 Model 80 mit VGA Monitor' },
        { title: 'Compaq Portable II Luggable' },
        { title: 'IBM ThinkPad 700C (1992)' },
        { title: 'Vintage ISA Karten Sammlung' },
        { title: '5,25" und 3,5" Diskettenlaufwerke' },
        { title: 'IBM Model M Tastaturen (3 Stück)' },
        { title: 'Original IBM DOS und OS/2 Softwaresammlung' },
        { title: 'PC-Peripherie Bundle (Mäuse, Kabel, Adapter)' },
        { title: 'Historische Fachzeitschriften 1983-1990' }
      ]
    }
  )

if result3.success?
  topic3 = result3.main_topic
  topic3.first_post.revise(users[2], raw: description3, edit_reason: 'Initial description')
  created_lotteries << topic3
  puts "✓ Lottery 3 created: #{topic3.title} (ID: #{topic3.id})"
else
  puts "✗ Failed to create lottery 3: #{result3.inspect}"
end

# ============================================================================
# Lottery 4: School Donation - Educational Hardware
# ============================================================================
puts "\n#{'=' * 80}"
puts 'Creating Lottery 4: Schulspende...'
puts '=' * 80

description4 = <<~DESC
  ## Über diese Verlosung

  Diese Hardware haben wir vom **Heinrich-Hertz-Gymnasium** in München erhalten. Die Schule hat ihren Informatikraum komplett modernisiert und dabei die historische Sammlung aus dem Archiv aufgelöst. Die stellvertretende Schulleiterin, Frau Dr. Müller, hat sich sehr gefreut, dass die Systeme eine zweite Chance bei Enthusiasten bekommen.

  Diese Geräte wurden von 1990 bis 2005 im Informatikunterricht eingesetzt und haben Generationen von Schülern die ersten Programmiererfahrungen ermöglicht. Einige Systeme tragen noch die originalen Inventaraufkleber der Schule.

  ## Behaltenes System

  Aus der Spende habe ich einen Apple IIe für mich behalten – mein Traum-Computer aus der Schulzeit, den ich jetzt endlich besitze.

  ## Übergabe der Pakete

  Ich habe alle Systeme am Gymnasium abgeholt.

  **Abholung:** Die Pakete können in 80687 München-Laim abgeholt werden. Ich kann flexible Termine anbieten, auch abends und am Wochenende.

  **Versand:** Versand ist möglich:
  - Versandkosten trägt der Gewinner
  - Monitore sollten möglichst abgeholt werden
  - Kleinere Systeme und Peripherie verschicke ich gerne

  **Fristen:**
  - Versand innerhalb von 1 Woche nach Kontaktaufnahme
  - Abholung innerhalb von 6 Wochen nach der Ziehung
  - Nicht abgeholte Pakete behalte ich
DESC

result4 =
  VzekcVerlosung::CreateLottery.call(
    user: users[3],
    guardian: Guardian.new(users[3]),
    params: {
      title: 'Spende Heinrich-Hertz-Gymnasium – Schul-IT der 90er Jahre',
      duration_days: 14,
      category_id: category_id.to_i,
      packets: [
        { title: 'Apple Macintosh Classic II Bundle' },
        { title: 'Apple PowerMac G3 Beige Desktop' },
        { title: 'Acorn RiscPC 600 mit Monitor' },
        { title: 'RM Nimbus PC-186 (UK Schulcomputer)' },
        { title: 'BBC Micro Model B mit Acorn Monitor' },
        { title: 'Apple IIe Europlus mit Disk II' },
        { title: 'Atari ST 1040F mit SM124 Monitor' },
        { title: 'Commodore PC-10 III (1987)' },
        { title: 'LOGO Turtle Roboter mit Interface' },
        { title: 'Bildungs-Software Sammlung (BBC, Apple, Atari)' },
        { title: 'Overhead-Projektor Folien mit BASIC Code' },
        { title: 'Original Informatik Lehrbücher 1985-2000' }
      ]
    }
  )

if result4.success?
  topic4 = result4.main_topic
  topic4.first_post.revise(users[3], raw: description4, edit_reason: 'Initial description')
  created_lotteries << topic4
  puts "✓ Lottery 4 created: #{topic4.title} (ID: #{topic4.id})"
else
  puts "✗ Failed to create lottery 4: #{result4.inspect}"
end

# ============================================================================
# Summary
# ============================================================================
puts "\n#{'=' * 80}"
puts 'SUMMARY'
puts '=' * 80
puts ''
puts "Successfully created #{created_lotteries.count} demo lotteries:"
puts ''

created_lotteries.each_with_index do |topic, index|
  puts "#{index + 1}. #{topic.title}"
  puts "   Owner: #{topic.user.username}"
  puts "   Topic ID: #{topic.id}"
  puts "   URL: #{topic.url}"
  puts ''
end

puts 'Next steps:'
puts '  1. Review and edit descriptions if needed'
puts '  2. Add detailed packet descriptions (photos, conditions, included items)'
puts '  3. Add test participants:'
puts '     LOAD_PLUGINS=1 bundle exec rails runner plugins/vzekc-verlosung/script/add_test_participants.rb <topic_id>'
puts '  4. Publish the lotteries via UI'
puts ''
