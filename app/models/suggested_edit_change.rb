# frozen_string_literal: true

class SuggestedEditChange < ActiveRecord::Base
  belongs_to :suggested_edit

  validates :start_offset,
            presence: true,
            numericality: {
              greater_than_or_equal_to: 0,
              only_integer: true,
            }

  def diff_html
    before_tokens = tokenize(CGI.escapeHTML(before_text))
    after_tokens = tokenize(CGI.escapeHTML(after_text))
    diff = ONPDiff.new(before_tokens, after_tokens).short_diff

    parts = []
    diff.each do |text, op|
      case op
      when :common
        parts << text
      when :delete
        parts << "<del class=\"diff-del\">#{text}</del>"
      when :add
        parts << "<ins class=\"diff-ins\">#{text}</ins>"
      end
    end

    "<div class=\"inline-diff\">#{parts.join}</div>"
  end

  private

  def tokenize(text)
    # Keep words and whitespace separate so newline-only deletions don't
    # force neighboring unchanged words into delete/add churn.
    text.scan(/[^\s]+|[ \t]+|\n+/)
  end
end

# == Schema Information
#
# Table name: suggested_edit_changes
#
#  id                :bigint           not null, primary key
#  after_text        :text             not null
#  before_text       :text             not null
#  position          :integer          not null
#  start_offset      :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  suggested_edit_id :bigint           not null
#
# Indexes
#
#  index_suggested_edit_changes_on_suggested_edit_id_and_position  (suggested_edit_id,position)
#
