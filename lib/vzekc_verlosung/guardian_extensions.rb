# frozen_string_literal: true

module VzekcVerlosung
  module GuardianExtensions
    # Check if user can create a post in a lottery draft topic
    #
    # @param topic [Topic] the topic to check
    # @return [Boolean] true if user can post, false otherwise
    def can_create_post_in_lottery_draft?(topic)
      return true unless topic&.custom_fields&.[]("lottery_state") == "draft"
      return true if is_staff?
      return true if topic.user_id == @user&.id

      false
    end
  end
end
