# frozen_string_literal: true

module VzekcVerlosung
  # Builds a pre-filled donation offer from the raw messages of an email thread
  # with a donor.
  #
  # The facilitator's own messages are recognised by their sender (an address of
  # the importing user or of one of the club domains) and skipped; everything
  # else is treated as written by the donor. The result holds a suggested title,
  # the pickup location, the donor's postal address, the post body (donor's
  # first message as a quote plus the photos) and the donor's messages for
  # review.
  class DonationEmailImport
    # Image attachments below this size are treated as signature logos and icons.
    MIN_IMAGE_BYTES = 15.kilobytes

    # Bounds the synchronous upload work of a single import.
    MAX_IMAGES = 40

    SUBJECT_PREFIX = /\A(?:\s*(?:re|aw|wg|fw|fwd|antw|antwort)\s*:\s*|\s*\[[^\]]*\]\s*)+/i

    # A line that introduces a quoted earlier message in a reply.
    REPLY_HEADER =
      /\A\s*(?:(?:am|on)\s.{4,120}\s(?:schrieb|wrote)\b|-{3,}\s*(?:original|ursprüngliche)|von:\s|from:\s)/i

    SALUTATION =
      /\A\s*(?:guten\s+(?:tag|morgen|abend)|hallo|hi|moin|servus|liebe|lieber|sehr\s+geehrte[rs]?)\b.{0,40}\z/i

    CLOSING =
      /\A\s*(?:mit\s+)?(?:(?:freundliche[nm]?|beste[n]?|herzliche[n]?|viele|liebe|schöne|sonnige)\s+){0,3}(?:grüßen|grüße|gruß|grüssen|grüsse|gruss)\b|\A\s*(?:mfg|lg|vg)\b[\s,.!]*(?:\p{Lu}[\p{L}.\-]*\s*){0,3}\z|\A\s*--\s*\z|\A\s*(?:gesendet|sent)\s+(?:von|mit|from)\b/i

    # Layout tables around inline images leave rows without any text.
    EMPTY_TABLE_ROW = /\A\s*\|[\s|:\-]*\|\s*\z/

    POSTCODE_LINE =
      /\A(?:(?:(?:D|DE)\s*-\s*)?(\d{5})|(?:A|AT|CH)\s*-\s*(\d{4}))\s+(\p{L}[\p{L}\p{M}.\-\/() ]{1,40}?)\.?\z/
    STREET_LINE =
      /\A(\p{L}[\p{L}\p{M}.\-' ]{1,50}?)\s+(\d{1,4}\s?[a-zA-Z]?(?:\s?[-\/]\s?\d{1,4}\s?[a-zA-Z]?)?)\z/
    STREET_AND_POSTCODE_LINE =
      /\A(\p{L}[\p{L}\p{M}.\-' ]{1,50}?)\s+(\d{1,4}\s?[a-zA-Z]?),\s*(\d{5})\s+(\p{L}[\p{L}\p{M}.\-\/() ]{1,40}?)\.?\z/
    STREET_IN_PROSE =
      /(\p{Lu}[\p{L}\-]*(?i:straße|strasse|str\.|weg|gasse|platz|allee|ring|damm|chaussee|ufer|steig|pfad))\s+(\d{1,4}\s?[a-z]?)\b/
    # A postcode in running text counts only after "in" ("abholbar in 12345 Musterstadt").
    POSTCODE_IN_PROSE =
      /\bin\s+(\d{5})\s+(\p{Lu}[\p{L}\-]+(?:\s+(?:a\.\s?d\.|an\s+der|am|im|bei|ob\s+der)\s+\p{Lu}[\p{L}\-]+)?)/
    LOCATION_LABEL = /\A\s*(?:standort|abholort)\s*:\s*(.{2,60}?)\s*\z/i
    # Contact lines that stay out of the public quote.
    CONTACT_LINE =
      /\b(?:tel|telefon|phone|mobil|mobile|handy|fax)\b\.?\s*:?\s*[+\d(]|\+\d{2}[\d\s\/()-]{6,}|\b0\d{2,5}[\s\/-]?\d{4,}\b|\b(?:e-?mail|adresse|anschrift)\s*:/i
    NAME_LINE = /\A\p{Lu}[\p{L}\p{M}.\-]*(?:\s+\p{Lu}[\p{L}\p{M}.\-]*){1,3}\z/

    Message =
      Struct.new(
        :from_name,
        :from_email,
        :date,
        :subject,
        :text,
        :images,
        :club,
        keyword_init: true,
      )

    # @param raw_messages [Array<String>] RFC 822 sources of the thread's messages
    # @param user [User] The importing facilitator; owns the created uploads
    def initialize(raw_messages, user)
      @raw_messages = raw_messages
      @user = user
    end

    # Parses the messages and uploads the donor's photos.
    #
    # @return [Hash] title, pickup_location, donor, raw, skipped_images, messages
    def call
      messages = parse_messages
      return nil if messages.empty?

      donor_messages = messages.reject(&:club)
      first = donor_messages.first

      donor = extract_donor(donor_messages)
      uploads, skipped = upload_images(donor_messages)

      {
        title: first ? clean_subject(first.subject) : "",
        pickup_location: extract_pickup_location(donor_messages, donor),
        donor: donor,
        raw: build_raw(first, donor, uploads),
        skipped_images: skipped,
        messages:
          messages.map do |m|
            {
              from: m.from_name.presence || m.from_email,
              email: m.from_email,
              date: m.date&.iso8601,
              subject: m.subject,
              text: m.text,
              donor: !m.club,
            }
          end,
      }
    end

    private

    def parse_messages
      @raw_messages
        .filter_map { |raw| parse_message(raw) }
        .uniq { |m| [m.from_email, m.text] }
        .sort_by { |m| m.date || Time.zone.at(0) }
    end

    # A message that cannot be parsed is skipped so the rest of the thread still imports.
    def parse_message(raw)
      receiver = Email::Receiver.new(raw)
      mail = receiver.mail
      from = mail[:from]
      address = from.respond_to?(:addrs) && from.addrs.first
      return nil unless address

      email = address.address.to_s.downcase
      Message.new(
        from_name: address.display_name.to_s.scrub.strip,
        from_email: email,
        date: mail.date.is_a?(DateTime) ? mail.date.to_time : nil,
        subject: mail.subject.to_s.scrub.strip,
        text: own_text(receiver, mail).scrub,
        images: image_parts(mail),
        club: club_address?(email),
      )
    rescue Email::Receiver::EmptyEmailError
      nil
    rescue StandardError => e
      Rails.logger.warn("Donation email import: skipping unparsable message: #{e.message}")
      nil
    end

    # The text written in this message, without quoted earlier messages.
    def own_text(receiver, mail)
      body =
        if mail.html_part || (!mail.multipart? && mail.content_type.to_s.include?("text/html"))
          html = receiver.fix_charset(mail.html_part || mail)
          HtmlToMarkdown.new(unwrap_preformatted(html.to_s)).to_markdown
        else
          part = mail.multipart? ? mail.text_part : mail
          unflow(receiver.fix_charset(part).to_s, part&.content_type.to_s)
        end

      lines = []
      body
        .gsub("\r\n", "\n")
        .tr(" ", " ")
        .each_line(chomp: true) do |line|
          break if line.gsub(/[*_\\]/, "").match?(REPLY_HEADER)
          next if line.lstrip.start_with?(">") || line.match?(EMPTY_TABLE_ROW)
          lines << line.rstrip
        end
      lines.join("\n").gsub(/\n{3,}/, "\n\n").strip
    end

    # Some mail clients send the whole message body as a <pre> block. Its lines
    # become <br>-separated text so the message reads as prose in the post.
    def unwrap_preformatted(html)
      document = Nokogiri.HTML5(html)
      return html if document.at_css("pre").nil?

      document
        .css("pre")
        .each do |pre|
          div = document.create_element("div")
          pre
            .text
            .split("\n", -1)
            .each_with_index do |line, index|
              div.add_child(document.create_element("br")) if index > 0
              div.add_child(document.create_text_node(line))
            end
          pre.replace(div)
        end
      document.to_html
    end

    # Joins the soft line breaks of format=flowed text (RFC 3676): a line ending
    # in a space continues on the next line. The signature separator "-- "
    # stays a line of its own.
    def unflow(text, content_type)
      return text unless content_type.match?(/format\s*=\s*["']?flowed/i)
      delete_space = content_type.match?(/delsp\s*=\s*["']?yes/i)

      text
        .gsub("\r\n", "\n")
        .split("\n", -1)
        .each_with_object([+""]) do |line, out|
          out[-1] << line
          soft = line.end_with?(" ") && line != "-- "
          if soft
            out[-1].chop! if delete_space
          else
            out << +""
          end
        end
        .join("\n")
    end

    def image_parts(mail)
      mail.all_parts.select do |part|
        part.mime_type.to_s.start_with?("image/") && part.body.decoded.bytesize >= MIN_IMAGE_BYTES
      end
    end

    def club_address?(email)
      return true if user_emails.include?(email)
      domain = email.split("@").last
      club_domains.include?(domain)
    end

    def user_emails
      @user_emails ||= @user.user_emails.pluck(:email).map(&:downcase)
    end

    def club_domains
      @club_domains ||=
        SiteSetting.vzekc_verlosung_email_import_club_domains.split("|").map { _1.strip.downcase }
    end

    def clean_subject(subject)
      cleaned = subject.sub(SUBJECT_PREFIX, "").strip
      generic =
        SiteSetting
          .vzekc_verlosung_email_import_generic_subjects
          .split("|")
          .map { _1.strip.downcase }
      generic.include?(cleaned.downcase) ? "" : cleaned
    end

    # Signature columns ("Musterweg 1        Tel: ...") are cut to their first column.
    def normalized_lines(text)
      text.lines.map { |line| line.gsub(/[*_]/, "").split(/\s{3,}|\t/).first.to_s.strip }
    end

    def extract_donor(donor_messages)
      donor = {
        name: "",
        company: "",
        email: "",
        street: "",
        street_number: "",
        postcode: "",
        city: "",
      }
      first = donor_messages.first
      return donor unless first

      donor[:email] = first.from_email
      donor[:name], donor[:company] = split_display_name(first.from_name)
      donor[:name] = signature_name(donor_messages) || donor[:name] if donor[:name].exclude?(" ")

      address = donor_messages.reverse_each.lazy.filter_map { postal_address(_1.text) }.first
      donor.merge!(address) if address
      donor
    end

    # "Jane Doe | Example Studios" carries the company after the bar.
    def split_display_name(display_name)
      name, company = display_name.to_s.delete('"').split(/\s+\|\s+/, 2)
      name = "" if name.to_s.include?("@")
      [name.to_s.strip, company.to_s.strip]
    end

    def signature_name(donor_messages)
      donor_messages.each do |message|
        lines = normalized_lines(message.text)
        closing = lines.index { _1.match?(CLOSING) }
        next unless closing
        name = lines[(closing + 1)..].find(&:present?)
        return name if name&.match?(NAME_LINE)
      end
      nil
    end

    def postal_address(text)
      lines = normalized_lines(text).reject(&:blank?)

      lines.each_with_index do |line, index|
        if (m = line.match(STREET_AND_POSTCODE_LINE))
          return { street: m[1], street_number: m[2], postcode: m[3], city: m[4] }
        end

        next unless (m = line.match(POSTCODE_LINE))
        address = { postcode: m[1] || m[2], city: m[3].strip }
        # "Erika Beispiel, Lindenweg 12a" carries the street after the last comma.
        street = index > 0 && lines[index - 1].split(",").last.to_s.strip.match(STREET_LINE)
        address.merge!(street: street[1], street_number: street[2]) if street
        return address
      end

      lines.each do |line|
        next unless (m = line.match(STREET_IN_PROSE))
        address = { street: m[1], street_number: m[2].strip }
        if (p = line.match(POSTCODE_IN_PROSE))
          address.merge!(postcode: p[1], city: p[2])
        end
        return address
      end

      nil
    end

    def extract_pickup_location(donor_messages, donor)
      donor_messages.each do |message|
        normalized_lines(message.text).each do |line|
          m = line.match(LOCATION_LABEL)
          return m[1].sub(/\s*\(.*\z/, "") if m
        end
      end

      return "#{donor[:postcode]} #{donor[:city]}" if donor[:postcode].present?

      donor_messages.each do |message|
        m = message.text.gsub(/[*_]/, "").match(POSTCODE_IN_PROSE)
        return "#{m[1]} #{m[2]}" if m
      end

      ""
    end

    # The donor's first message without salutation, closing, signature and
    # contact details, for the public post.
    def offer_text(message, donor)
      lines = message.text.lines.map(&:rstrip)
      lines.shift while lines.first&.blank?
      lines.shift if lines.first&.match?(SALUTATION)
      closing = lines.index { _1.match?(CLOSING) }
      lines = lines[0...closing] if closing
      lines.reject { |line| contact_line?(line, donor) }.join("\n").gsub(/\n{3,}/, "\n\n").strip
    end

    def contact_line?(line, donor)
      plain = line.gsub(/[*_]/, "").strip
      return false if plain.empty?
      return true if plain.match?(CONTACT_LINE)
      return true if donor[:email].present? && plain.downcase.include?(donor[:email])

      street = "#{donor[:street]} #{donor[:street_number]}".strip
      return true if donor[:street].present? && plain.include?(street)

      donor[:postcode].present? &&
        plain.sub(/\A(?:[A-Z]{1,2}\s*-\s*)/, "").chomp(".") == "#{donor[:postcode]} #{donor[:city]}"
    end

    def build_raw(first, donor, uploads)
      quote =
        if first
          offer_text(first, donor)
            .lines
            .map { |line| line.strip.empty? ? ">" : "> #{line.rstrip}" }
            .join("\n")
        else
          ""
        end
      images = uploads.map { UploadMarkdown.new(_1).image_markdown }.join("\n\n")

      SiteSetting
        .vzekc_verlosung_donation_email_template
        .gsub("[QUOTE]") { quote }
        .gsub("[IMAGES]") { images }
        .strip
    end

    def upload_images(donor_messages)
      uploads = []
      skipped = []
      seen = Set.new

      donor_messages.each do |message|
        message.images.each_with_index do |part, index|
          data = part.body.decoded
          next unless seen.add?(Digest::SHA1.hexdigest(data))

          filename = part.filename.to_s.scrub.presence || "image-#{index + 1}.#{part.sub_type}"
          if uploads.size >= MAX_IMAGES
            skipped << filename
            next
          end

          upload = create_upload(data, filename)
          upload&.persisted? && upload.errors.empty? ? uploads << upload : skipped << filename
        end
      end

      [uploads, skipped]
    end

    def create_upload(data, filename)
      tempfile = Tempfile.new(["donation-email-image", File.extname(filename)])
      tempfile.binmode
      tempfile.write(data)
      tempfile.rewind
      UploadCreator.new(tempfile, filename, type: "composer").create_for(@user.id)
    rescue StandardError => e
      Rails.logger.warn("Donation email import: could not upload #{filename}: #{e.message}")
      nil
    ensure
      tempfile&.close!
    end
  end
end
