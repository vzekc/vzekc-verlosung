# frozen_string_literal: true

module VzekcVerlosung
  module GuardianExtensions
    # Override can_create_post to check lottery draft status
    #
    # @param topic [Topic] the topic to check
    # @return [Boolean] true if user can post, false otherwise
    def can_create_post?(topic)
      return false unless super
      can_create_post_in_lottery_draft?(topic)
    end

    # Check if user can create a post in a lottery topic
    # Now that draft state is removed, this just checks if the topic is a lottery
    # and allows posts (lottery posting is controlled elsewhere)
    #
    # @param topic [Topic] the topic to check
    # @return [Boolean] true if user can post, false otherwise
    def can_create_post_in_lottery_draft?(topic)
      lottery = VzekcVerlosung::Lottery.find_by(topic_id: topic&.id)
      return true unless lottery

      # Active lotteries: staff and lottery owner can post
      return true if is_staff?
      return true if @user && !is_anonymous? && topic.user_id == @user.id

      # For active lotteries, regular users can post (e.g., lottery tickets via likes)
      true
    end

    # Check if user can manage lottery packets (mark as collected, etc.)
    #
    # @param topic [Topic] the lottery topic
    # @return [Boolean] true if user is lottery owner or staff
    def can_manage_lottery_packets?(topic)
      return false unless topic
      return true if is_staff?
      return true if topic.user_id == @user&.id

      false
    end

    # Check if user can manage a donation
    #
    # @param donation [Donation] the donation to check
    # @return [Boolean] true if user is donation creator or staff
    def can_manage_donation?(donation)
      return false unless donation
      return true if is_staff?
      return true if donation.creator_user_id == @user&.id

      false
    end

    # Check if user can offer to pick up a donation
    #
    # @param donation [Donation] the donation to check
    # @return [Boolean] true if user can offer pickup
    def can_offer_pickup?(donation)
      return false unless @user
      return false unless donation.open?

      # Can't offer if already has an offer (any state)
      !VzekcVerlosung::PickupOffer.exists?(donation_id: donation.id, user_id: @user.id)
    end

    # Override can_delete_post to prevent deletion of lottery packet posts
    #
    # @param post [Post] the post to check
    # @return [Boolean] true if user can delete, false otherwise
    def can_delete_post?(post)
      # Check if this is a lottery packet post
      if VzekcVerlosung::LotteryPacket.exists?(post_id: post.id)
        # Lottery packet posts cannot be deleted individually
        # They must be deleted by deleting the entire lottery topic
        return false
      end

      # For non-packet posts, use the default Guardian logic
      super
    end
  end
end
