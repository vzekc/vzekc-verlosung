# frozen_string_literal: true

class CreateNotificationLogs < ActiveRecord::Migration[7.2]
  def change
    create_table :vzekc_verlosung_notification_logs do |t|
      t.bigint :recipient_user_id, null: false
      t.string :notification_type, null: false
      t.string :delivery_method, null: false
      t.bigint :lottery_id
      t.bigint :donation_id
      t.bigint :lottery_packet_id
      t.bigint :topic_id
      t.bigint :post_id
      t.bigint :actor_user_id
      t.jsonb :payload
      t.boolean :success, null: false, default: true
      t.string :error_message
      t.datetime :created_at, null: false
    end

    add_index :vzekc_verlosung_notification_logs, :recipient_user_id
    add_index :vzekc_verlosung_notification_logs, :lottery_id
    add_index :vzekc_verlosung_notification_logs, :donation_id
    add_index :vzekc_verlosung_notification_logs, :notification_type
    add_index :vzekc_verlosung_notification_logs, :created_at
    add_index :vzekc_verlosung_notification_logs,
              %i[recipient_user_id created_at],
              name: "idx_notification_logs_on_recipient_and_created"
    add_index :vzekc_verlosung_notification_logs,
              %i[lottery_id notification_type],
              name: "idx_notification_logs_on_lottery_and_type"

    add_foreign_key :vzekc_verlosung_notification_logs,
                    :users,
                    column: :recipient_user_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_notification_logs,
                    :users,
                    column: :actor_user_id,
                    on_delete: :nullify
    add_foreign_key :vzekc_verlosung_notification_logs,
                    :vzekc_verlosung_lotteries,
                    column: :lottery_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_notification_logs,
                    :vzekc_verlosung_donations,
                    column: :donation_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_notification_logs,
                    :vzekc_verlosung_lottery_packets,
                    column: :lottery_packet_id,
                    on_delete: :cascade
    add_foreign_key :vzekc_verlosung_notification_logs,
                    :topics,
                    column: :topic_id,
                    on_delete: :nullify
    add_foreign_key :vzekc_verlosung_notification_logs,
                    :posts,
                    column: :post_id,
                    on_delete: :nullify
  end
end
