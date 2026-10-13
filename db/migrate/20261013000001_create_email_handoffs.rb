# frozen_string_literal: true

class CreateEmailHandoffs < ActiveRecord::Migration[7.2]
  def change
    create_table :vzekc_verlosung_email_handoffs do |t|
      t.string :token_digest, null: false
      t.string :invocation_id, null: false
      t.string :herold_user_email
      t.string :thread_subject
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :vzekc_verlosung_email_handoffs, :token_digest, unique: true
    add_index :vzekc_verlosung_email_handoffs, :invocation_id, unique: true
    add_index :vzekc_verlosung_email_handoffs, :expires_at

    create_table :vzekc_verlosung_email_handoff_messages do |t|
      t.bigint :email_handoff_id, null: false
      t.integer :position, null: false
      t.binary :raw, null: false
    end

    add_index :vzekc_verlosung_email_handoff_messages, :email_handoff_id
    add_foreign_key :vzekc_verlosung_email_handoff_messages,
                    :vzekc_verlosung_email_handoffs,
                    column: :email_handoff_id,
                    on_delete: :cascade
  end
end
