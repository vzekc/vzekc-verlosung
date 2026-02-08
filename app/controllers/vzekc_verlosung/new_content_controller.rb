# frozen_string_literal: true

module VzekcVerlosung
  # Controller for checking if there is new (unread) content for the current user
  #
  # Returns boolean flags for each sidebar section indicating whether
  # new content exists that the user hasn't read yet.
  #
  class NewContentController < ::ApplicationController
    requires_plugin VzekcVerlosung::PLUGIN_NAME

    before_action :ensure_logged_in

    # GET /vzekc-verlosung/has-new-content.json
    #
    # @return [JSON] { donations: bool, lotteries: bool, erhaltungsberichte: bool, merch_packets: bool }
    def index
      render json: {
               donations: VzekcVerlosung.has_unread_donations?(current_user.id),
               lotteries: VzekcVerlosung.has_unread_lotteries?(current_user.id),
               erhaltungsberichte: VzekcVerlosung.has_unread_erhaltungsberichte?(current_user.id),
               merch_packets: has_pending_merch_packets?,
             }
    end

    private

    # Check for pending merch packets (only for merch handlers)
    #
    # @return [Boolean]
    def has_pending_merch_packets?
      return false unless guardian.can_manage_merch_packets?

      VzekcVerlosung.has_pending_merch_packets?
    end
  end
end
