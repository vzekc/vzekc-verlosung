# frozen_string_literal: true

require "rails_helper"

describe VzekcVerlosung::DonationsController do
  fab!(:facilitator, :user)
  fab!(:other_user, :user)

  before { SiteSetting.vzekc_verlosung_enabled = true }

  describe "#create" do
    let(:address_params) do
      {
        postcode: "10115",
        donor_name: "Max Mustermann",
        donor_street: "Musterstraße",
        donor_street_number: "42",
        donor_postcode: "12345",
        donor_city: "Musterstadt",
      }
    end

    before { sign_in(facilitator) }

    it "creates the merch packet with the donor's email" do
      post "/vzekc-verlosung/donations.json",
           params: address_params.merge(donor_email: "max@example.com")

      expect(response.status).to eq(200)
      donation = VzekcVerlosung::Donation.find(response.parsed_body["donation_id"])
      expect(donation.merch_packet.donor_email).to eq("max@example.com")
    end

    it "returns 422 when the donor's email is missing" do
      expect { post "/vzekc-verlosung/donations.json", params: address_params }.not_to change {
        VzekcVerlosung::Donation.count
      }

      expect(response.status).to eq(422)
      expect(response.parsed_body["errors"]).to include(
        I18n.t("vzekc_verlosung.errors.donor_email_required"),
      )
    end

    it "creates a donation without a merch packet when no donor data is given" do
      post "/vzekc-verlosung/donations.json", params: { postcode: "10115" }

      expect(response.status).to eq(200)
      donation = VzekcVerlosung::Donation.find(response.parsed_body["donation_id"])
      expect(donation.merch_packet).to be_nil
    end
  end

  describe "#show" do
    fab!(:donation) { Fabricate(:donation, creator_user_id: facilitator.id, state: "open") }
    fab!(:merch_packet) do
      Fabricate(:merch_packet, donation: donation, donor_email: "max@example.com")
    end

    context "as the facilitator" do
      before { sign_in(facilitator) }

      it "includes the donor's name and email" do
        get "/vzekc-verlosung/donations/#{donation.id}.json"

        expect(response.status).to eq(200)
        expect(response.parsed_body["donation"]["donor_contact"]).to eq(
          "name" => "Max Mustermann",
          "email" => "max@example.com",
        )
      end

      it "omits the donor contact once the merch packet is archived" do
        merch_packet.update!(state: "shipped", shipped_at: 5.weeks.ago)
        merch_packet.archive!

        get "/vzekc-verlosung/donations/#{donation.id}.json"

        expect(response.parsed_body["donation"]["donor_contact"]).to be_nil
      end
    end

    context "as another user" do
      before { sign_in(other_user) }

      it "omits the donor contact" do
        get "/vzekc-verlosung/donations/#{donation.id}.json"

        expect(response.status).to eq(200)
        expect(response.parsed_body["donation"]["donor_contact"]).to be_nil
      end
    end
  end

  describe "#import_email" do
    let(:eml) do
      Mail
        .new do
          from "Erika Beispiel <erika@example.com>"
          to "info@classic-computing.de"
          subject "Alter Rechner"
          body "Ein Rechner.\n\nLindenweg 1\n12345 Musterstadt"
        end
        .to_s
    end

    let(:eml_file) do
      Rack::Test::UploadedFile.new(
        StringIO.new(eml),
        "message/rfc822",
        original_filename: "offer.eml",
      )
    end

    it "requires a logged in user" do
      post "/vzekc-verlosung/donations/import-email.json", params: { files: [eml_file] }

      expect(response.status).to eq(403)
    end

    context "when logged in" do
      before { sign_in(facilitator) }

      it "returns the pre-filled offer without creating a donation" do
        expect {
          post "/vzekc-verlosung/donations/import-email.json", params: { files: [eml_file] }
        }.not_to change { VzekcVerlosung::Donation.count }

        expect(response.status).to eq(200)
        expect(response.parsed_body["title"]).to eq("Alter Rechner")
        expect(response.parsed_body["donor"]).to include(
          "email" => "erika@example.com",
          "postcode" => "12345",
        )
      end

      it "returns 422 when no file is an email message" do
        junk =
          Rack::Test::UploadedFile.new(
            StringIO.new("just text"),
            "text/plain",
            original_filename: "notes.txt",
          )

        post "/vzekc-verlosung/donations/import-email.json", params: { files: [junk] }

        expect(response.status).to eq(422)
      end

      it "imports the .eml entries of a zip file" do
        require "zip"
        zip =
          Zip::OutputStream.write_buffer do |out|
            out.put_next_entry("01-offer.eml")
            out.write(eml)
            out.put_next_entry("notes.txt")
            out.write("ignored")
          end
        zip_file =
          Rack::Test::UploadedFile.new(
            StringIO.new(zip.string),
            "application/zip",
            original_filename: "thread.zip",
          )

        post "/vzekc-verlosung/donations/import-email.json", params: { files: [zip_file] }

        expect(response.status).to eq(200)
        expect(response.parsed_body["messages"].size).to eq(1)
      end

      it "imports a zip whose entries use data descriptors" do
        zip_file =
          Rack::Test::UploadedFile.new(
            File.expand_path("../../fixtures/files/thread-with-data-descriptors.zip", __dir__),
            "application/zip",
          )

        post "/vzekc-verlosung/donations/import-email.json", params: { files: [zip_file] }

        expect(response.status).to eq(200)
        expect(response.parsed_body["messages"].size).to eq(2)
      end

      it "returns 422 without files" do
        post "/vzekc-verlosung/donations/import-email.json"

        expect(response.status).to eq(422)
      end
    end
  end
end
