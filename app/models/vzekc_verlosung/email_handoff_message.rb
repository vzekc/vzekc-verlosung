# frozen_string_literal: true

# == Schema Information
#
# Table name: vzekc_verlosung_email_handoff_messages
#
#  id               :bigint           not null, primary key
#  position         :integer          not null
#  raw              :binary           not null
#  email_handoff_id :bigint           not null
#
# Indexes
#
#  idx_on_email_handoff_id_31ea4df248  (email_handoff_id)
#
# Foreign Keys
#
#  fk_rails_...  (email_handoff_id => vzekc_verlosung_email_handoffs.id) ON DELETE => cascade
#
module VzekcVerlosung
  # One raw RFC 822 message of an email handoff.
  class EmailHandoffMessage < ActiveRecord::Base
    self.table_name = "vzekc_verlosung_email_handoff_messages"

    belongs_to :email_handoff, class_name: "VzekcVerlosung::EmailHandoff"
  end
end
