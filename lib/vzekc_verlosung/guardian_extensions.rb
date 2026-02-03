# frozen_string_literal: true

module VzekcVerlosung
  module GuardianExtensions
    # Check if user can create a lottery in the given category
    # This bypasses the normal category topic creation block
    #
    # @param category [Category] the category to check
    # @return [Boolean] true if user can create lottery
    def can_create_lottery?(category)
      return false unless @user
      return false unless category

      # Check if user has general topic creation ability
      @user.in_any_groups?(SiteSetting.create_topic_allowed_groups_map)
    end

    # Override to block normal topic creation in lottery categories
    # Users must use the lottery creation flow instead
    #
    # @param category [Category] the category to check
    # @return [Boolean] true if user can create topic
    def can_create_topic_on_category?(category)
      return super unless category

      lottery_category_id = SiteSetting.vzekc_verlosung_category_id.to_i
      return super if lottery_category_id <= 0

      # Block topic creation in lottery category
      return false if category.id == lottery_category_id

      # Block topic creation in subcategories of lottery category
      return false if category.parent_category_id == lottery_category_id

      super
    end

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

      # Lottery owner can always post
      return true if @user && !is_anonymous? && topic.user_id == @user.id

      # For active lotteries, regular users can post (e.g., lottery tickets via likes)
      true
    end

    # Check if user can manage lottery packets (mark as collected, etc.)
    #
    # @param topic [Topic] the lottery topic
    # @return [Boolean] true if user is lottery owner
    def can_manage_lottery_packets?(topic)
      return false unless topic
      topic.user_id == @user&.id
    end

    # Check if user can manage a donation
    #
    # @param donation [Donation] the donation to check
    # @return [Boolean] true if user is donation creator (facilitator)
    def can_manage_donation?(donation)
      return false unless donation
      donation.creator_user_id == @user&.id
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

    # Check if user can manage merch packets
    #
    # @return [Boolean] true if user is in merch handlers group
    def can_manage_merch_packets?
      return false unless @user

      group_name = SiteSetting.vzekc_verlosung_merch_handlers_group_name
      return false if group_name.blank?

      group = Group.find_by(name: group_name)
      return false unless group

      group.users.exists?(id: @user.id)
    end
  end
end
