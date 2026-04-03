# frozen_string_literal: true

class CreateSuggestedEditChanges < ActiveRecord::Migration[7.2]
  def change
    unless table_exists?(:suggested_edit_changes)
      create_table :suggested_edit_changes do |t|
        t.bigint :suggested_edit_id, null: false
        t.integer :position, null: false
        t.integer :start_offset, null: false
        t.text :before_text, null: false
        t.text :after_text, null: false
        t.timestamps
      end

      add_index :suggested_edit_changes, %i[suggested_edit_id position], unique: true
      add_foreign_key :suggested_edit_changes, :suggested_edits, on_delete: :cascade
    end
  end
end
