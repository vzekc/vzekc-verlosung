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
          .joins(:donation)
          .includes(donation: :topic)
          .where.not(state: "archived")
          .where(vzekc_verlosung_donations: { state: %w[picked_up closed] })
          .order(created_at: :desc)

      render json: {
               merch_packets:
                 packets.map do |packet|
                   serialize_merch_packet(packet)
                 end,
             }
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

      head :no_content
    end

    private

    def ensure_can_manage_merch_packets
      return if guardian.can_manage_merch_packets?

      render_json_error(
        "You don't have permission to manage merch packets",
        status: :forbidden,
      )
    end

    def serialize_merch_packet(packet)
      donation = packet.donation
      topic = donation&.topic

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
        formatted_address: packet.formatted_address,
        tracking_info: packet.tracking_info,
        shipped_at: packet.shipped_at,
        created_at: packet.created_at,
        donation: {
          id: donation&.id,
          topic_id: topic&.id,
          title: topic&.title,
          url: topic&.url,
        },
      }
    end
  end
end
