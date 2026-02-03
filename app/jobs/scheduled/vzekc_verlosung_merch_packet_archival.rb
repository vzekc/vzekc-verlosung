# frozen_string_literal: true

module Jobs
  class VzekcVerlosungMerchPacketArchival < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      archived_count = 0

      VzekcVerlosung::MerchPacket.needs_archival.find_each do |packet|
        packet.archive!
        archived_count += 1
        Rails.logger.info(
          "Archived merch packet #{packet.id} (donation_id: #{packet.donation_id})",
        )
      rescue => e
        Rails.logger.error(
          "Failed to archive merch packet #{packet.id}: #{e.message}",
        )
      end

      Rails.logger.info("Merch packet archival job completed. Archived #{archived_count} packets.") if archived_count.positive?
    end
  end
end
