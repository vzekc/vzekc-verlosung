# frozen_string_literal: true

class AddErhaltungsberichtTopicIdToDonations < ActiveRecord::Migration[7.2]
  def change
    add_column :vzekc_verlosung_donations, :erhaltungsbericht_topic_id, :bigint

    add_index :vzekc_verlosung_donations,
              :erhaltungsbericht_topic_id,
              unique: true,
              name: "index_donations_on_erhaltungsbericht_topic_id"

    # Add foreign key to topics table
    add_foreign_key :vzekc_verlosung_donations,
                    :topics,
                    column: :erhaltungsbericht_topic_id,
                    on_delete: :nullify
  end
end
