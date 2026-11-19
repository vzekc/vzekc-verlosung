# frozen_string_literal: true

module VzekcVerlosung
  # Restricts a controller to users who may take part in lotteries and
  # donations (see Guardian#can_participate_in_lotteries?). Controllers that
  # serve an HTML shell page skip the check for that action with
  # skip_before_action :ensure_lottery_participant.
  module RequiresLotteryParticipant
    extend ActiveSupport::Concern

    included { before_action :ensure_lottery_participant }

    private

    def ensure_lottery_participant
      raise Discourse::NotLoggedIn unless current_user
      raise Discourse::InvalidAccess unless guardian.can_participate_in_lotteries?
    end
  end
end
