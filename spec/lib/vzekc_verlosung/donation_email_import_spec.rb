# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::DonationEmailImport do
  fab!(:facilitator) { Fabricate(:user, email: "facilitator@example.org") }

  let(:photo) { file_from_fixtures("logo.jpg").read }
  let(:icon) { file_from_fixtures("logo.png").read }

  def build_mail(from:, subject:, body:, date: "2026-09-10 12:00", to: "info@classic-computing.de")
    mail =
      Mail.new do
        from from
        to to
        subject subject
        date Time.zone.parse(date)
        text_part do
          content_type "text/plain; charset=UTF-8"
          body body
        end
      end
    yield mail if block_given?
    mail.to_s
  end

  let(:offer) do
    build_mail(from: "Erika Beispiel <erika@example.com>", subject: "Alter Rechner", body: <<~TEXT)
      Guten Tag,

      ich habe einen alten Rechner mit Monitor abzugeben.

      Er stand lange im Keller.

      Freundliche Grüße aus Musterstadt

      Erika Beispiel
      Lindenweg 12a
      12345 Musterstadt
      Tel.: 01234 56789
    TEXT
  end

  let(:facilitator_reply) do
    build_mail(
      from: "Vorstand <vorsitz@classic-computing.de>",
      to: "erika@example.com",
      subject: "Re: Alter Rechner",
      date: "2026-09-10 13:00",
      body: "Vielen Dank! Meine Adresse ist Vereinsweg 1, 10115 Berlin.",
    )
  end

  def import(*raws)
    described_class.new(raws, facilitator).call
  end

  it "extracts the donor, the pickup location and the offer from the donor's message" do
    result = import(offer, facilitator_reply)

    expect(result[:title]).to eq("Alter Rechner")
    expect(result[:pickup_location]).to eq("12345 Musterstadt")
    expect(result[:donor]).to include(
      name: "Erika Beispiel",
      email: "erika@example.com",
      street: "Lindenweg",
      street_number: "12a",
      postcode: "12345",
      city: "Musterstadt",
    )
    expect(result[:raw]).to eq(<<~MD.strip)
      Wir erhielten folgendes Angebot:

      > ich habe einen alten Rechner mit Monitor abzugeben.
      >
      > Er stand lange im Keller.

      Wer kümmert sich?
    MD
    expect(result[:messages].map { _1[:donor] }).to eq([true, false])
  end

  it "takes the address from a later donor reply and ignores quoted text" do
    reply =
      build_mail(
        from: "Erika Beispiel <erika@example.com>",
        subject: "Re: Alter Rechner",
        date: "2026-09-10 14:00",
        body: <<~TEXT,
          Ich wohne in Musterstadt in der Robert-Beispiel-Straße 6.

          Am 10.09.26 um 15:00 schrieb Vorstand:
          Vielen Dank! Meine Adresse ist Vereinsweg 1, 10115 Berlin.
        TEXT
      )
    first =
      build_mail(from: "erika@example.com", subject: "Rechner", body: "Hallo,\n\nein Rechner.")

    result = import(first, facilitator_reply, reply)

    expect(result[:donor]).to include(street: "Robert-Beispiel-Straße", street_number: "6")
    expect(result[:donor][:postcode]).to eq("")
  end

  it "ignores the quoted history of an Outlook HTML reply" do
    html = <<~HTML
      <p>Gerne, hier noch ein Foto.</p>
      <div id="divRplyFwdMsg"><b>Von:</b> Vorstand &lt;vorsitz@classic-computing.de&gt;<br>
      <b>Gesendet:</b> Mittwoch<br></div>
      <p>Meine Adresse ist<br>Vereinsweg 1<br>10115 Berlin</p>
    HTML
    reply =
      Mail.new do
        from "erika@example.com"
        subject "AW: Alter Rechner"
        date Time.zone.parse("2026-09-11 10:00")
        html_part do
          content_type "text/html; charset=UTF-8"
          body html
        end
      end

    result = import(offer, reply.to_s)

    expect(result[:donor]).to include(street: "Lindenweg", postcode: "12345")
    expect(result[:messages].last[:text]).not_to include("Vereinsweg")
  end

  it "keeps contact details of a signature without closing out of the quote" do
    body = <<~TEXT
      Ich habe einen LG Monitor 24 Zoll und einen Drucker, abholbar in 12345 Musterstadt.
      Erika Beispiel, Lindenweg 12a
      12345 Musterstadt
      Telefon: 01234 567890
      erika@example.com
    TEXT
    raw = import(build_mail(from: "erika@example.com", subject: "Monitor", body: body))[:raw]

    expect(raw).to include(
      "> Ich habe einen LG Monitor 24 Zoll und einen Drucker, abholbar in 12345 Musterstadt.",
    )
    expect(raw).not_to include("Lindenweg")
    expect(raw).not_to include("01234")
    expect(raw).not_to include("erika@example.com")
  end

  it "skips a message whose sender cannot be parsed" do
    broken = "From: <<<\r\nSubject: kaputt\r\n\r\nText"

    expect(import(broken, offer)[:messages].size).to eq(1)
  end

  it "returns nil when no file is an email message" do
    expect(import("not an email at all")).to be_nil
  end

  it "treats messages from the importing user's own address as the facilitator's" do
    own = build_mail(from: "facilitator@example.org", subject: "Re: Alter Rechner", body: "Danke")

    expect(import(offer, own)[:messages].map { _1[:donor] }).to eq([true, false])
  end

  it "suggests no title for a generic contact form subject" do
    form =
      build_mail(
        from: "erika@example.com",
        subject: "VzEkC e.V. - Anfrage ueber die Website",
        body: "Ein Rechner.",
      )

    expect(import(form)[:title]).to eq("")
  end

  it "strips reply prefixes and tags from the subject" do
    mail =
      build_mail(
        from: "erika@example.com",
        subject: "AW: [trace2] Alter Rechner",
        body: "Ein Rechner.",
      )

    expect(import(mail)[:title]).to eq("Alter Rechner")
  end

  it "splits a company off the sender's display name" do
    mail =
      build_mail(
        from: "Max Muster | Beispiel Studios <max@example.com>",
        subject: "Laufwerk",
        body: "Ein Laufwerk.",
      )

    expect(import(mail)[:donor]).to include(name: "Max Muster", company: "Beispiel Studios")
  end

  it "takes the name from the signature when the display name is not a full name" do
    mail =
      build_mail(
        from: "M.Muster <m@example.com>",
        subject: "Drucker",
        body: "Ein Drucker.\n\nMit freundlichen Grüßen\n\nMax Muster",
      )

    expect(import(mail)[:donor][:name]).to eq("Max Muster")
  end

  it "joins the soft line breaks of flowed text and ends the quote at the closing" do
    mail =
      build_mail(
        from: "erika@example.com",
        subject: "Laufwerk",
        body: "Ein Laufwerk im \nRackgehäuse.\n\nViele herzliche Grüsse,\nErika Beispiel\n",
      ) { |m| m.text_part.content_type = "text/plain; charset=UTF-8; format=flowed" }

    expect(import(mail)[:raw]).to include("> Ein Laufwerk im Rackgehäuse.\n\nWer kümmert sich?")
  end

  it "reads an Austrian address from a signature laid out in columns" do
    body = <<~TEXT
      Ich habe ein Terminal abzugeben.
      Standort: Wien (kann versendet werden)

      --
      Dr. Max Muster            m:  +43 664 123
      Beispielgasse 13          t:  +43 2231 456
      A-3002  Purkersdorf       e:  max@example.at
    TEXT
    result =
      import(build_mail(from: "Max Muster <max@example.at>", subject: "Terminal", body: body))

    expect(result[:pickup_location]).to eq("Wien")
    expect(result[:donor]).to include(
      street: "Beispielgasse",
      street_number: "13",
      postcode: "3002",
      city: "Purkersdorf",
    )
  end

  it "uploads each of the donor's photos once and skips small images" do
    with_photos = ->(mail) do
      mail.add_file(filename: "foto.jpg", content: photo)
      mail.add_file(filename: "logo.png", content: icon)
    end
    first =
      build_mail(from: "erika@example.com", subject: "Rechner", body: "Ein Rechner.", &with_photos)
    again =
      build_mail(
        from: "erika@example.com",
        subject: "Re: Rechner",
        date: "2026-09-11 10:00",
        body: "Nochmal.",
        &with_photos
      )

    result = nil
    expect { result = import(first, again) }.to change { Upload.count }.by(1)

    upload = Upload.last
    expect(upload.user_id).to eq(facilitator.id)
    expect(result[:raw]).to include(
      "![foto.jpg|#{upload.width}x#{upload.height}](#{upload.short_url})",
    )
    expect(result[:skipped_images]).to eq([])
  end
end
