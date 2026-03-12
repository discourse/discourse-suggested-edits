# frozen_string_literal: true

class CreateSuggestedEdits < ActiveRecord::Migration[7.2]
  def change
    create_table :suggested_edits do |t|
      t.bigint :post_id, null: false
      t.bigint :user_id, null: false
      t.text :raw_suggestion, null: false
      t.integer :base_post_version, null: false
      t.integer :status, null: false, default: 0
      t.bigint :applied_by_id
      t.datetime :applied_at
      t.text :reason
      t.timestamps
    end

    add_index :suggested_edits, %i[post_id status]
    add_index :suggested_edits, :user_id
    add_index :suggested_edits, :status
    add_index :suggested_edits,
              %i[post_id user_id],
              unique: true,
              where: "status = 0",
              name: "idx_pending_suggested_edits_on_post_user"

    add_foreign_key :suggested_edits, :posts, on_delete: :cascade
    add_foreign_key :suggested_edits, :users
    add_foreign_key :suggested_edits, :users, column: :applied_by_id, on_delete: :nullify
  end
end
