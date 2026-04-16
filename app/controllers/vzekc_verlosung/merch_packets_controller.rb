# frozen_string_literal: true

module VzekcVerlosung
  # Controller for managing merch packet fulfillment
  #
  # Merch handlers can view pending packets and mark them as shipped.
  #
  class MerchPacketsController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in
    before_action :ensure_can_manage_merch_packets

    # GET /vzekc-verlosung/merch-packets
    #
    # Lists all merch packets for merch handlers
    #
    # @return [JSON] Array of merch packets with donation info
    def index
      packets =
        MerchPacket
          .left_joins(:donation)
          .includes(donation: :topic)
          .references(:vzekc_verlosung_donations)
          .where.not(vzekc_verlosung_merch_packets: { state: "archived" })
          .where(
            "vzekc_verlosung_donations.state IN (?) OR vzekc_verlosung_merch_packets.donation_id IS NULL",
            %w[picked_up closed],
          )
          .order(created_at: :desc)

      render json: { merch_packets: packets.map { |packet| serialize_merch_packet(packet) } }
    end

    # POST /vzekc-verlosung/merch-packets
    #
    # Creates a standalone merch packet (not linked to a donation)
    #
    # @param title [String] Required title for the packet
    # @param donor_name [String] Donor's name
    # @param donor_company [String] Optional company
    # @param donor_street [String] Street name
    # @param donor_street_number [String] Street number
    # @param donor_postcode [String] Postal code
    # @param donor_city [String] City
    # @param donor_email [String] Optional email
    #
    # @return [JSON] Serialized merch packet (201)
    def create
      packet =
        MerchPacket.new(
          title: params[:title],
          donor_name: params[:donor_name],
          donor_company: params[:donor_company],
          donor_street: params[:donor_street],
          donor_street_number: params[:donor_street_number],
          donor_postcode: params[:donor_postcode],
          donor_city: params[:donor_city],
          donor_email: params[:donor_email],
          state: "pending",
        )

      if packet.save
        render json: { merch_packet: serialize_merch_packet(packet) }, status: :created
      else
        render_json_error(packet)
      end
    end

    # PUT /vzekc-verlosung/merch-packets/:id
    #
    # Updates a pending merch packet's address fields
    #
    # @param id [Integer] Merch packet ID
    #
    # @return [HTTP 204] No content on success
    def update
      packet = MerchPacket.find(params[:id])

      unless packet.pending?
        return render_json_error("Packet is not pending", status: :unprocessable_entity)
      end

      update_params =
        params.permit(
          :title,
          :donor_name,
          :donor_company,
          :donor_street,
          :donor_street_number,
          :donor_postcode,
          :donor_city,
          :donor_email,
        )

      if packet.update(update_params)
        render json: { merch_packet: serialize_merch_packet(packet) }
      else
        render_json_error(packet)
      end
    end

    # PUT /vzekc-verlosung/merch-packets/:id/ship
    #
    # Marks a merch packet as shipped
    #
    # @param id [Integer] Merch packet ID
    # @param tracking_info [String] Optional tracking information
    #
    # @return [HTTP 204] No content on success
    def ship
      packet = MerchPacket.find(params[:id])

      unless packet.pending?
        return render_json_error("Packet is not pending", status: :unprocessable_entity)
      end

      packet.mark_shipped!(current_user, tracking_info: params[:tracking_info])

      handler_ids = VzekcVerlosung.merch_handler_user_ids
      if handler_ids.any?
        has_new = VzekcVerlosung.has_pending_merch_packets?
        VzekcVerlosung.notify_new_content("merch_packets", user_ids: handler_ids, has_new: has_new)
      end

      head :no_content
    end

    # GET /vzekc-verlosung/merch-packets/stats
    #
    # Returns monthly shipping statistics (all time, including archived)
    #
    # @return [JSON] Array of { month: "YYYY-MM", count: N }
    def stats
      rows =
        MerchPacket
          .where.not(shipped_at: nil)
          .group(Arel.sql("TO_CHAR(shipped_at, 'YYYY-MM')"))
          .order(Arel.sql("TO_CHAR(shipped_at, 'YYYY-MM')"))
          .count

      render json: { stats: rows.map { |month, count| { month: month, count: count } } }
    end

    private

    def ensure_can_manage_merch_packets
      return if guardian.can_manage_merch_packets?

      render_json_error("You don't have permission to manage merch packets", status: :forbidden)
    end

    def serialize_merch_packet(packet)
      donation = packet.donation
      topic = donation&.topic

      result = {
        id: packet.id,
        state: packet.state,
        title: packet.display_title,
        donor_name: packet.donor_name,
        donor_company: packet.donor_company,
        donor_street: packet.donor_street,
        donor_street_number: packet.donor_street_number,
        donor_postcode: packet.donor_postcode,
        donor_city: packet.donor_city,
        donor_email: packet.donor_email,
        formatted_address: packet.formatted_address,
        tracking_info: packet.tracking_info,
        shipped_at: packet.shipped_at,
        created_at: packet.created_at,
      }

      if donation
        result[:donation] = {
          id: donation.id,
          topic_id: topic&.id,
          title: topic&.title,
          url: topic&.url,
        }
      end

      result
    end
  end
end
