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
    text.scan(/[^\s]+\s*|\s+/)
  end
end
