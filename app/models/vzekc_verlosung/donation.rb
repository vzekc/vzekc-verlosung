# frozen_string_literal: true

module VzekcVerlosung
  # Model for donation offers
  #
  # Roles:
  # - donor: Person who has hardware to give away (not in system)
  # - facilitator: User who creates donation offer, finds picker, provides donor contact (creator_user_id)
  # - picker: User who picks up donation, then keeps it or creates lottery
  #
  # @attr topic_id [Integer] Associated Discourse topic (set after topic creation)
  # @attr state [String] Current state: draft, open, assigned, picked_up, closed
  # @attr postcode [String] Location postcode for pickup
  # @attr creator_user_id [Integer] The facilitator who created the donation offer
  # @attr published_at [DateTime] When the donation was published (changed to 'open')
  #
  class Donation < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_donations"

    belongs_to :topic, optional: true
    belongs_to :facilitator, class_name: "User", foreign_key: :creator_user_id
    belongs_to :erhaltungsbericht_topic, class_name: "Topic", optional: true
    # Alias for backwards compatibility
    alias_method :creator, :facilitator
    has_many :pickup_offers, dependent: :destroy
    has_many :lottery_interests, dependent: :destroy
    has_one :lottery, class_name: "VzekcVerlosung::Lottery", dependent: :nullify
    has_one :merch_packet, class_name: "VzekcVerlosung::MerchPacket", dependent: :destroy
    belongs_to :onsite_lottery_event,
               class_name: "VzekcVerlosung::OnsiteLotteryEvent",
               optional: true

    validates :state, presence: true, inclusion: { in: %w[draft open assigned picked_up closed] }
    validates :postcode, presence: true
    validates :creator_user_id, presence: true
    validate :ensure_exclusive_outcome

    private

    # Ensure a donation can have at most one outcome:
    # lottery, Erhaltungsbericht, or onsite lottery event
    def ensure_exclusive_outcome
      outcomes = 0
      outcomes += 1 if lottery.present?
      outcomes += 1 if erhaltungsbericht_topic_id.present?
      outcomes += 1 if onsite_lottery_event_id.present?
      return if outcomes <= 1

      errors.add(
        :base,
        "A donation can only have one outcome (lottery, Erhaltungsbericht, " \
          "or onsite lottery event). Please choose one.",
      )
    end

    public

    # State scopes
    scope :draft, -> { where(state: "draft") }
    scope :open, -> { where(state: "open") }
    scope :assigned, -> { where(state: "assigned") }
    scope :picked_up, -> { where(state: "picked_up") }
    scope :closed, -> { where(state: "closed") }
    scope :needs_reminder,
          lambda {
            open.where("published_at IS NOT NULL").where(
              "last_reminded_at IS NULL OR last_reminded_at < ?",
              24.hours.ago,
            )
          }
    scope :needs_pickup_action_reminder,
          lambda {
            where(state: %w[picked_up closed]).where(
              "last_reminded_at IS NULL OR last_reminded_at < ?",
              7.days.ago,
            )
          }

    # State helper methods
    #
    # @return [Boolean] true if in draft state
    def draft?
      state == "draft"
    end

    # @return [Boolean] true if in open state
    def open?
      state == "open"
    end

    # @return [Boolean] true if in assigned state
    def assigned?
      state == "assigned"
    end

    # @return [Boolean] true if in picked_up state
    def picked_up?
      state == "picked_up"
    end

    # @return [Boolean] true if in closed state
    def closed?
      state == "closed"
    end

    # Publish the donation (draft → open)
    #
    # @return [Boolean] true if successful
    def publish!
      update!(state: "open", published_at: Time.zone.now)
    end

    # Select the pickup offer that should receive the donation when
    # auto-assigning. The offer whose picker has collected the fewest
    # donations so far wins. Ties are broken with a deterministic,
    # donation-seeded RNG so that repeated calls (e.g. cancelling and
    # re-submitting the auto-assign form) always yield the same picker.
    #
    # @return [Hash, nil] selection details or nil when there are no pending
    #   offers. Keys:
    #   - :offer [PickupOffer] the chosen offer
    #   - :method [String] "least_collected" or "random"
    #   - :min_count [Integer] the (lowest) collected count of the candidates
    #   - :tied_offers [Array<PickupOffer>] candidates sharing the lowest count
    def auto_assign_selection
      candidates = pickup_offers.pending.includes(:user).to_a
      return nil if candidates.empty?

      counts = candidates.index_with { |offer| PickupOffer.collected_count(offer.user_id) }
      min_count = counts.values.min
      tied = candidates.select { |offer| counts[offer] == min_count }.sort_by(&:user_id)

      if tied.size == 1
        { offer: tied.first, method: "least_collected", min_count: min_count, tied_offers: tied }
      else
        rng = Random.new(auto_assign_seed)
        {
          offer: tied[rng.rand(tied.size)],
          method: "random",
          min_count: min_count,
          tied_offers: tied,
        }
      end
    end

    # Whether manually assigning to +offer+ deviates from the fair-distribution
    # rule: there is more than one pending offer and the chosen picker has
    # collected more donations than the lowest count among the offerers.
    #
    # @param offer [PickupOffer] the offer the facilitator wants to assign
    # @return [Boolean]
    def assignment_diverges?(offer)
      pending = pickup_offers.pending.includes(:user).to_a
      return false if pending.size <= 1

      min_count = pending.map { |o| PickupOffer.collected_count(o.user_id) }.min
      PickupOffer.collected_count(offer.user_id) > min_count
    end

    # Assign donation to a specific pickup offer
    #
    # @param pickup_offer [PickupOffer] The offer to assign
    # @param contact_info [String] Contact information from donation creator
    # @param actor [User] The user who triggered the assignment
    # @param method [String] "manual", "least_collected" or "random"
    # @param tied_offers [Array<PickupOffer>] candidates for a random assignment
    # @param collected_count [Integer] shared collected count for a random assignment
    # @param explanation [String] facilitator's justification for a manual
    #   assignment that diverges from the fair-distribution rule
    # @return [Boolean] true if successful
    def assign_to!(
      pickup_offer,
      contact_info: nil,
      actor: nil,
      method: "manual",
      tied_offers: [],
      collected_count: nil,
      explanation: nil
    )
      transaction do
        update!(state: "assigned")
        # Mark the selected offer as assigned
        pickup_offer.update!(state: "assigned", assigned_at: Time.zone.now)
        # Keep other offers visible but in pending state for transparency
      end
      # Send notification PM to assigned user
      send_assignment_notification!(pickup_offer, contact_info) if contact_info.present?
      # Post a status reply documenting the assignment. Manual assignments are
      # authored by the facilitator, automatic ones by the system account.
      post_assignment_response!(
        pickup_offer,
        actor: actor,
        method: method,
        tied_offers: tied_offers,
        collected_count: collected_count,
        explanation: explanation,
      )
    end

    # Mark donation as picked up
    # Picker will then choose to either keep it (write Erhaltungsbericht) or create lottery
    #
    # @return [Boolean] true if successful
    def mark_picked_up!
      transaction do
        # Set last_reminded_at to prevent duplicate reminder on same day
        update!(state: "picked_up", last_reminded_at: Time.zone.now)
        # Update the assigned offer
        assigned_offer = pickup_offers.find_by(state: "assigned")
        assigned_offer&.update!(state: "picked_up", picked_up_at: Time.zone.now)
      end
      # Auto-close after pickup
      close_automatically!
      # Send initial PM notification to picker about next steps
      send_pickup_notification!
      # Notify merch handlers if a merch packet exists
      notify_merch_handlers!
    end

    # Close the donation
    #
    # @return [Boolean] true if successful
    def close!
      update!(state: "closed")
    end

    # Check if the picker has completed required action after pickup
    # Returns true if either:
    # - A lottery was created and published (active/finished state)
    # - An Erhaltungsbericht was created for this donation
    #
    # @return [Boolean] true if action completed
    def pickup_action_completed?
      # Check if lottery was published (not just draft)
      return true if lottery&.active? || lottery&.finished?

      # Check if an Erhaltungsbericht exists for this donation (use direct association)
      return true if erhaltungsbericht_topic_id.present?

      # Check if assigned to an onsite lottery event
      onsite_lottery_event_id.present?
    end

    private

    # Send PM notification when donation offer is assigned to a picker
    #
    # @param pickup_offer [PickupOffer] The assigned offer
    # @param contact_info [String] Donor's contact information provided by facilitator
    def send_assignment_notification!(pickup_offer, contact_info)
      return unless topic

      picker = pickup_offer.user
      return unless picker

      NotificationService.notify(
        :donation_assigned,
        recipient: picker,
        context: {
          donation: self,
          contact_info: contact_info,
        },
      )
    end

    # Deterministic RNG seed for tie-breaking during auto-assignment.
    # Derived from the donation id so the random pick is stable across
    # repeated calls for the same donation.
    #
    # @return [Integer]
    def auto_assign_seed
      Digest::MD5.hexdigest("vzekc-verlosung-auto-assign-#{id}")[0, 8].to_i(16)
    end

    # Join user mentions into a localized German-style list:
    # "A und B" for two, "A, B und C" for three or more.
    #
    # @param mentions [Array<String>]
    # @return [String]
    def join_mentions(mentions)
      return mentions.first.to_s if mentions.size <= 1

      *head, tail = mentions
      "#{head.join(", ")} #{I18n.t("vzekc_verlosung.assignment_post.and")} #{tail}"
    end

    # Post a public German reply to the donation topic documenting who
    # assigned the donation, to whom, and how (manually, automatically by
    # fewest collections, or randomly between tied pickers).
    #
    # @param pickup_offer [PickupOffer] the assigned offer
    # @param actor [User] the user who triggered the assignment
    # @param method [String] "manual", "least_collected" or "random"
    # @param tied_offers [Array<PickupOffer>] candidates for a random assignment
    # @param collected_count [Integer] shared collected count for a random assignment
    # @param explanation [String] facilitator's justification for a diverging
    #   manual assignment
    def post_assignment_response!(
      pickup_offer,
      actor:,
      method:,
      tied_offers:,
      collected_count:,
      explanation:
    )
      return unless topic
      return unless actor

      picker = pickup_offer.user
      return unless picker

      # Manual assignments are authored by the facilitator (first person);
      # automatic ones by the system account (naming the facilitator).
      author = method == "manual" ? actor : Discourse.system_user

      raw =
        case method
        when "least_collected"
          I18n.t(
            "vzekc_verlosung.assignment_post.least_collected",
            actor: "@#{actor.username}",
            picker: "@#{picker.username}",
            count: collected_count,
          )
        when "random"
          candidates = join_mentions(tied_offers.map { |offer| "@#{offer.user.username}" })
          scope = tied_offers.size == 2 ? "two" : "many"
          I18n.t(
            "vzekc_verlosung.assignment_post.random.#{scope}",
            actor: "@#{actor.username}",
            picker: "@#{picker.username}",
            candidates: candidates,
            count: collected_count,
          )
        else
          key = explanation.present? ? "assignment_post.manual_override" : "assignment_post.manual"
          I18n.t("vzekc_verlosung.#{key}", picker: "@#{picker.username}", explanation: explanation)
        end

      begin
        PostCreator.create!(author, topic_id: topic_id, raw: raw, skip_validations: true)
      rescue StandardError => e
        # The assignment itself has already succeeded; a failure to post the
        # status reply must never surface as an error to the facilitator.
        Rails.logger.error(
          "[VzekcVerlosung] Failed to post assignment response for donation #{id}: #{e.class}: #{e.message}",
        )
      end
    end

    # Automatically close donation after pickup
    def close_automatically!
      close! if picked_up?
    end

    # Notify merch handlers that a merch packet is ready to ship
    def notify_merch_handlers!
      return unless merch_packet&.pending?

      NotificationService.notify_merch_handlers(donation: self)
    end

    # Send initial PM notification when donation is marked as picked up
    # Reminds picker to either write Erhaltungsbericht or create lottery
    def send_pickup_notification!
      return unless topic

      # Get the assigned offer (picker)
      assigned_offer = pickup_offers.find_by(state: %w[assigned picked_up])
      return unless assigned_offer

      picker = assigned_offer.user
      return unless picker

      NotificationService.notify(
        :donation_picked_up_reminder,
        recipient: picker,
        context: {
          donation: self,
        },
      )
    end
  end
end

# == Schema Information
#
# Table name: vzekc_verlosung_donations
#
#  id                         :bigint           not null, primary key
#  last_reminded_at           :datetime
#  postcode                   :string           not null
#  published_at               :datetime
#  state                      :string           default("draft"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  creator_user_id            :bigint           not null
#  erhaltungsbericht_topic_id :bigint
#  onsite_lottery_event_id    :bigint
#  topic_id                   :bigint
#
# Indexes
#
#  index_donations_on_erhaltungsbericht_topic_id               (erhaltungsbericht_topic_id) UNIQUE
#  index_vzekc_verlosung_donations_on_creator_user_id          (creator_user_id)
#  index_vzekc_verlosung_donations_on_onsite_lottery_event_id  (onsite_lottery_event_id)
#  index_vzekc_verlosung_donations_on_state                    (state)
#  index_vzekc_verlosung_donations_on_state_and_published_at   (state,published_at)
#  index_vzekc_verlosung_donations_on_topic_id                 (topic_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (creator_user_id => users.id) ON DELETE => cascade
#  fk_rails_...  (erhaltungsbericht_topic_id => topics.id) ON DELETE => nullify
#  fk_rails_...  (onsite_lottery_event_id => vzekc_verlosung_onsite_lottery_events.id) ON DELETE => nullify
#  fk_rails_...  (topic_id => topics.id) ON DELETE => cascade
#
