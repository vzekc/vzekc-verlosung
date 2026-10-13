# frozen_string_literal: true

module VzekcVerlosung
  # Controller for managing donation offers
  #
  # Roles:
  # - donor: Person who has hardware to give away (not in system)
  # - facilitator: Creates donation offer, finds picker, provides donor contact
  # - picker: Picks up donation, then keeps it or creates lottery
  #
  class DonationsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    EMAIL_IMPORT_MAX_FILES = 20
    EMAIL_IMPORT_MAX_ZIP_ENTRIES = 100
    EMAIL_IMPORT_MAX_ZIP_ENTRY_BYTES = 30.megabytes
    EMAIL_IMPORT_MAX_TOTAL_BYTES = 60.megabytes

    before_action :ensure_logged_in

    # GET /vzekc-verlosung/donations/:id
    #
    # Gets the current state of a donation
    #
    # @param id [Integer] Donation ID
    #
    # @return [JSON] Donation details including current state and lottery link if created.
    #   Includes the donor's name and email (donor_contact) for the facilitator so the
    #   picker-assignment form can be pre-filled.
    def show
      donation = Donation.find(params[:id])

      lottery_topic = donation.lottery&.topic
      lottery_data =
        if lottery_topic
          { id: donation.lottery.id, topic_id: lottery_topic.id, url: lottery_topic.url }
        end

      # Use direct association instead of custom field query
      erhaltungsbericht_topic = donation.erhaltungsbericht_topic
      erhaltungsbericht_data =
        if erhaltungsbericht_topic
          { id: erhaltungsbericht_topic.id, url: erhaltungsbericht_topic.url }
        end

      onsite_lottery_event = donation.onsite_lottery_event
      onsite_lottery_event_data =
        if onsite_lottery_event
          {
            id: onsite_lottery_event.id,
            name: onsite_lottery_event.name,
            event_date: onsite_lottery_event.event_date,
          }
        end

      render json: {
               donation: {
                 id: donation.id,
                 state: donation.state,
                 postcode: donation.postcode,
                 topic_id: donation.topic_id,
                 creator_user_id: donation.creator_user_id,
                 published_at: donation.published_at,
                 lottery_id: donation.lottery&.id,
                 lottery: lottery_data,
                 erhaltungsbericht: erhaltungsbericht_data,
                 onsite_lottery_event: onsite_lottery_event_data,
                 donor_contact: build_donor_contact(donation),
               },
             }
    end

    # POST /vzekc-verlosung/donations
    #
    # Creates a new donation in draft state (no topic yet)
    #
    # @param postcode [String] Location postcode for pickup
    # @param donor_name [String] Optional: Donor name for merch packet
    # @param donor_company [String] Optional: Donor company/zusatz
    # @param donor_street [String] Optional: Donor street
    # @param donor_street_number [String] Optional: Donor street number
    # @param donor_postcode [String] Optional: Donor postcode
    # @param donor_city [String] Optional: Donor city
    # @param donor_email [String] Donor email, required when a merch packet is created
    #
    # @return [JSON] donation_id for use in composer
    def create
      if create_params[:donor_name].present? && create_params[:donor_email].blank?
        return(
          render_json_error(
            I18n.t("vzekc_verlosung.errors.donor_email_required"),
            status: :unprocessable_entity,
          )
        )
      end

      donation =
        Donation.create!(postcode: create_params[:postcode], creator_user_id: current_user.id)

      # Create merch packet if donor address is provided
      create_merch_packet_if_provided(donation)

      render json: success_json.merge(donation_id: donation.id)
    rescue ActiveRecord::RecordInvalid => e
      render json: failed_json.merge(errors: e.record.errors.full_messages),
             status: :unprocessable_entity
    end

    # POST /vzekc-verlosung/donations/import-email
    #
    # Pre-fills a donation offer from the email thread with the donor. Uploads
    # the donor's photos and returns the suggested form values and post body;
    # nothing else is stored until the facilitator submits the form.
    #
    # @param files [Array<ActionDispatch::Http::UploadedFile>] The thread's messages as
    #   .eml files, or zip files of .eml files
    # @param handoff_token [String] Alternatively, the one-time token of a thread handed
    #   over by Herold (EmailHandoff)
    #
    # @return [JSON] title, pickup_location, donor, raw, skipped_images, messages
    def import_email
      RateLimiter.new(current_user, "vzekc-donation-email-import", 30, 1.hour).performed!

      return import_from_handoff(params[:handoff_token]) if params[:handoff_token].present?

      files = Array.wrap(params[:files]).select { _1.respond_to?(:read) }
      return import_error("email_import_no_files") if files.empty?
      if files.size > EMAIL_IMPORT_MAX_FILES
        return import_error("email_import_too_many_files", count: EMAIL_IMPORT_MAX_FILES)
      end

      result = DonationEmailImport.new(raw_messages_from_files(files), current_user).call
      return import_error("email_import_no_messages") if result.nil?

      render json: result
    end

    # PUT /vzekc-verlosung/donations/:id/publish
    #
    # Publishes a draft donation (changes state to open)
    #
    # @param id [Integer] Donation ID
    #
    # @return [HTTP 204] No content on success
    def publish
      donation = Donation.find(params[:id])

      unless guardian.can_manage_donation?(donation)
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      unless donation.draft?
        return render_json_error("Donation is not in draft state", status: :unprocessable_entity)
      end

      donation.publish!
      VzekcVerlosung.notify_new_content("donations")

      head :no_content
    end

    # GET /vzekc-verlosung/donations/pending
    #
    # Returns donations where current user is the picker and hasn't completed the required action
    # (i.e., hasn't created a lottery or written an Erhaltungsbericht)
    #
    # @return [JSON] Array of pending donations
    def pending
      # Find donations where current user is the assigned/picked_up picker
      pending_donations =
        Donation
          .where(state: %w[picked_up closed])
          .joins(:pickup_offers)
          .where(
            vzekc_verlosung_pickup_offers: {
              user_id: current_user.id,
              state: %w[assigned picked_up],
            },
          )
          .includes(:topic, :lottery)
          .select { |d| !d.pickup_action_completed? && d.topic.present? }

      render json: {
               donations:
                 pending_donations.map do |d|
                   { id: d.id, topic_id: d.topic_id, title: d.topic.title }
                 end,
             }
    end

    # PUT /vzekc-verlosung/donations/:id/close
    #
    # Closes a donation (manual close by creator)
    #
    # @param id [Integer] Donation ID
    #
    # @return [HTTP 204] No content on success
    def close
      donation = Donation.find(params[:id])

      unless guardian.can_manage_donation?(donation)
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      donation.close!

      head :no_content
    end

    # PUT /vzekc-verlosung/donations/:donation_id/merch-packet
    #
    # Updates merch packet address for a donation
    #
    # @return [HTTP 204] No content on success
    def update_merch_packet
      donation = Donation.find(params[:donation_id])

      unless guardian.can_manage_donation?(donation) || guardian.can_manage_merch_packets?
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      packet = donation.merch_packet
      return render_json_error("No merch packet found", status: :not_found) unless packet

      unless packet.pending?
        return(
          render_json_error("Merch packet has already been shipped", status: :unprocessable_entity)
        )
      end

      if packet.update(merch_packet_params)
        head :no_content
      else
        render_json_error(packet)
      end
    end

    # POST /vzekc-verlosung/donations/:donation_id/merch-packet
    #
    # Creates a merch packet for a donation that doesn't have one
    #
    # @return [JSON] Merch packet data (201)
    def create_merch_packet
      donation = Donation.find(params[:donation_id])

      unless guardian.can_manage_donation?(donation) || guardian.can_manage_merch_packets?
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      if donation.merch_packet.present?
        return(
          render_json_error("Donation already has a merch packet", status: :unprocessable_entity)
        )
      end

      packet = MerchPacket.new(merch_packet_params.merge(donation: donation, state: "pending"))

      if packet.save
        render json: { merch_packet: serialize_donation_merch_packet(packet) }, status: :created
      else
        render_json_error(packet)
      end
    end

    # DELETE /vzekc-verlosung/donations/:donation_id/merch-packet
    #
    # Deletes a pending merch packet for a donation
    #
    # @return [HTTP 204] No content on success
    def destroy_merch_packet
      donation = Donation.find(params[:donation_id])

      unless guardian.can_manage_donation?(donation) || guardian.can_manage_merch_packets?
        return(
          render_json_error("You don't have permission to manage this donation", status: :forbidden)
        )
      end

      packet = donation.merch_packet
      return render_json_error("No merch packet found", status: :not_found) unless packet

      unless packet.pending?
        return(
          render_json_error("Merch packet has already been shipped", status: :unprocessable_entity)
        )
      end

      packet.destroy!

      handler_ids = VzekcVerlosung.merch_handler_user_ids
      if handler_ids.any?
        has_new = VzekcVerlosung.has_pending_merch_packets?
        VzekcVerlosung.notify_new_content("merch_packets", user_ids: handler_ids, has_new: has_new)
      end

      head :no_content
    end

    private

    # The handoff is deleted only once the import produced a result, so a
    # failed import leaves the link usable until it expires.
    def import_from_handoff(token)
      found = false
      result =
        EmailHandoff.consume(token) do |raws|
          found = true
          DonationEmailImport.new(raws, current_user).call
        end
      return import_error("email_import_handoff_gone", status: :gone) unless found
      return import_error("email_import_no_messages") if result.nil?

      render json: result
    end

    def import_error(key, status: :unprocessable_entity, **args)
      render_json_error(I18n.t("vzekc_verlosung.errors.#{key}", **args), status: status)
    end

    # Reads uploaded .eml files; zip files contribute each .eml entry they hold.
    # Entries over EMAIL_IMPORT_MAX_ZIP_ENTRY_BYTES are skipped, and reading
    # stops once EMAIL_IMPORT_MAX_TOTAL_BYTES have been collected.
    #
    # @param files [Array<ActionDispatch::Http::UploadedFile>]
    # @return [Array<String>] Raw messages
    def raw_messages_from_files(files)
      require "zip"
      budget = EMAIL_IMPORT_MAX_TOTAL_BYTES
      raws = []

      files.each do |file|
        data = file.read
        unless data.start_with?("PK\x03\x04".b)
          break if data.bytesize > budget
          budget -= data.bytesize
          raws << data
          next
        end

        Zip::File.open_buffer(StringIO.new(data)) do |zip|
          zip
            .entries
            .first(EMAIL_IMPORT_MAX_ZIP_ENTRIES)
            .each do |entry|
              next unless entry.file? && entry.name.downcase.end_with?(".eml")
              next if entry.size > EMAIL_IMPORT_MAX_ZIP_ENTRY_BYTES || entry.size > budget

              content = entry.get_input_stream.read(EMAIL_IMPORT_MAX_ZIP_ENTRY_BYTES + 1).to_s
              next if content.empty? || content.bytesize > EMAIL_IMPORT_MAX_ZIP_ENTRY_BYTES
              budget -= content.bytesize
              raws << content
            end
        end
      rescue Zip::Error
        next
      end

      raws
    end

    def merch_packet_params
      params.permit(
        :donor_name,
        :donor_company,
        :donor_street,
        :donor_street_number,
        :donor_postcode,
        :donor_city,
        :donor_email,
      )
    end

    def serialize_donation_merch_packet(packet)
      {
        id: packet.id,
        state: packet.state,
        donor_name: packet.donor_name,
        donor_company: packet.donor_company,
        donor_street: packet.donor_street,
        donor_street_number: packet.donor_street_number,
        donor_postcode: packet.donor_postcode,
        donor_city: packet.donor_city,
        donor_email: packet.donor_email,
      }
    end

    def create_params
      params.permit(
        :postcode,
        :donor_name,
        :donor_company,
        :donor_street,
        :donor_street_number,
        :donor_postcode,
        :donor_city,
        :donor_email,
      )
    end

    # The donor's name and email address for pre-filling the picker-assignment
    # form. Only the facilitator receives it, and only while the merch packet
    # still holds the donor's personal data.
    #
    # @param donation [Donation] The donation
    # @return [Hash, nil] name and email, or nil
    def build_donor_contact(donation)
      return nil unless guardian.can_manage_donation?(donation)

      packet = donation.merch_packet
      return nil if packet.nil? || packet.archived?

      { name: packet.donor_name, email: packet.donor_email }
    end

    # Create a merch packet if donor address fields are provided
    #
    # @param donation [Donation] The donation to create the merch packet for
    def create_merch_packet_if_provided(donation)
      return if create_params[:donor_name].blank?

      MerchPacket.create!(
        donation: donation,
        donor_name: create_params[:donor_name],
        donor_company: create_params[:donor_company],
        donor_street: create_params[:donor_street],
        donor_street_number: create_params[:donor_street_number],
        donor_postcode: create_params[:donor_postcode],
        donor_city: create_params[:donor_city],
        donor_email: create_params[:donor_email],
      )
    end
  end
end
