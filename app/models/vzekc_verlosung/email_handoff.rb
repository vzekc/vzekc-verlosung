# frozen_string_literal: true

# == Schema Information
#
# Table name: vzekc_verlosung_email_handoffs
#
#  id                :bigint           not null, primary key
#  expires_at        :datetime         not null
#  herold_user_email :string
#  thread_subject    :string
#  token_digest      :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  invocation_id     :string           not null
#
# Indexes
#
#  index_vzekc_verlosung_email_handoffs_on_expires_at     (expires_at)
#  index_vzekc_verlosung_email_handoffs_on_invocation_id  (invocation_id) UNIQUE
#  index_vzekc_verlosung_email_handoffs_on_token_digest   (token_digest) UNIQUE
#
module VzekcVerlosung
  # An email thread handed over by Herold (a thread action invocation), waiting
  # to be opened by a logged-in facilitator. The browser receives only a
  # one-time token; the table stores its SHA-256 digest.
  class EmailHandoff < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_email_handoffs"

    TTL = 15.minutes

    has_many :messages,
             -> { order(:position) },
             class_name: "VzekcVerlosung::EmailHandoffMessage",
             dependent: :delete_all

    scope :expired, -> { where("expires_at <= ?", Time.zone.now) }

    # @param token [String] The one-time token from the handoff URL
    # @return [String] Digest stored for the token
    def self.digest(token)
      Digest::SHA256.hexdigest(token.to_s)
    end

    # Yields the raw messages of an unexpired handoff and deletes the handoff
    # when the block returns a truthy result, so a token works for one
    # successful import. The handoff row stays locked while the block runs.
    #
    # @param token [String] The one-time token from the handoff URL
    # @yieldparam raws [Array<String>] Raw RFC 822 messages
    # @return [Object, nil] The block's result, or nil when no handoff matches
    def self.consume(token)
      transaction do
        handoff = lock.where("expires_at > ?", Time.zone.now).find_by(token_digest: digest(token))
        next nil unless handoff

        result = yield handoff.messages.pluck(:raw)
        handoff.destroy! if result
        result
      end
    end
  end
end
