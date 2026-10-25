# frozen_string_literal: true

module Jobs
  class VzekcVerlosungDonorContactPurge < ::Jobs::Scheduled
    every 1.day

    def execute(args)
      return unless SiteSetting.vzekc_verlosung_enabled

      VzekcVerlosung::Donation.needs_donor_contact_purge.find_each do |donation|
        donation.purge_donor_contact!
        Rails.logger.info("Purged donor contact of donation #{donation.id}")
      rescue => e
        Rails.logger.error("Failed to purge donor contact of donation #{donation.id}: #{e.message}")
      end
    end
  end
end
