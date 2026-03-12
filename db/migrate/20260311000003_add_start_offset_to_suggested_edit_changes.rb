# frozen_string_literal: true

class AddStartOffsetToSuggestedEditChanges < ActiveRecord::Migration[7.2]
  PENDING_STATUS = 0
  STALE_STATUS = 3

  def up
    return unless table_exists?(:suggested_edit_changes)

    unless column_exists?(:suggested_edit_changes, :start_offset)
      add_column :suggested_edit_changes, :start_offset, :integer
    end

    say_with_time "Backfilling suggested edit change offsets" do
      suggestions.each { |suggested_edit| backfill_suggested_edit(suggested_edit) }
    end

    change_column_null :suggested_edit_changes, :start_offset, false
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def suggestions
    DB.query(<<~SQL)
      SELECT se.id,
             se.status,
             se.base_post_version,
             se.raw_suggestion,
             p.raw AS post_raw,
             p.version AS post_version
      FROM suggested_edits se
      LEFT JOIN posts p ON p.id = se.post_id
      WHERE EXISTS (
        SELECT 1
        FROM suggested_edit_changes sec
        WHERE sec.suggested_edit_id = se.id
      )
      ORDER BY se.id
    SQL
  end

  def changes_for_suggestion(suggested_edit_id)
    sql = <<~SQL
      SELECT id, position, before_text, after_text
      FROM suggested_edit_changes
      WHERE suggested_edit_id = :suggested_edit_id
      ORDER BY position
    SQL

    DB.query(sql, suggested_edit_id: suggested_edit_id)
  end

  def backfill_suggested_edit(suggested_edit)
    changes = changes_for_suggestion(suggested_edit.id)
    return if changes.blank?

    post_raw = suggested_edit.post_raw.to_s

    if suggested_edit.status == PENDING_STATUS &&
         suggested_edit.post_version.to_i > suggested_edit.base_post_version.to_i
      sql = <<~SQL
        UPDATE suggested_edits
        SET status = :stale_status,
            updated_at = NOW()
        WHERE id = :suggested_edit_id
      SQL

      DB.exec(sql, suggested_edit_id: suggested_edit.id, stale_status: STALE_STATUS)
    end

    if suggested_edit.post_version.to_i == suggested_edit.base_post_version.to_i
      extracted_changes = extract_changes(post_raw, suggested_edit.raw_suggestion.to_s)

      if extracted_changes.length == changes.length
        changes
          .zip(extracted_changes)
          .each do |change, extracted_change|
            sql = <<~SQL
            UPDATE suggested_edit_changes
            SET start_offset = :start_offset,
                before_text = :before_text,
                after_text = :after_text,
                updated_at = NOW()
            WHERE id = :change_id
          SQL

            DB.exec(
              sql,
              change_id: change.id,
              start_offset: extracted_change[:start_offset],
              before_text: extracted_change[:before_text],
              after_text: extracted_change[:after_text],
            )
          end

        return
      end
    end

    backfill_offsets_from_current_post(changes, post_raw)
  end

  def backfill_offsets_from_current_post(changes, post_raw)
    cursor = 0

    changes.each do |change|
      offset =
        if change.before_text.present?
          post_raw.index(change.before_text, cursor) || post_raw.index(change.before_text) || cursor
        else
          [cursor, post_raw.length].min
        end

      sql = <<~SQL
        UPDATE suggested_edit_changes
        SET start_offset = :start_offset,
            updated_at = NOW()
        WHERE id = :change_id
      SQL

      DB.exec(sql, change_id: change.id, start_offset: offset)

      cursor = offset + change.before_text.to_s.length
    end
  end

  def extract_changes(original_raw, new_raw)
    diff_result = ONPDiff.new(original_raw.lines, new_raw.lines).short_diff

    original_offset = 0
    current_start_offset = nil
    current_before = []
    current_after = []
    changes = []

    flush =
      lambda do
        next if current_start_offset.nil?

        changes << {
          start_offset: current_start_offset,
          before_text: current_before.join,
          after_text: current_after.join,
        }

        current_start_offset = nil
        current_before = []
        current_after = []
      end

    diff_result.each do |text, op|
      case op
      when :common
        flush.call
        original_offset += text.length
      when :delete
        current_start_offset ||= original_offset
        current_before << text
        original_offset += text.length
      when :add
        current_start_offset ||= original_offset
        current_after << text
      end
    end

    flush.call

    changes
  end
end
