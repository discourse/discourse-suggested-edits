# frozen_string_literal: true

module DiscourseSuggestedEdits
  class ChangeApplier
    class MismatchError < StandardError
    end

    def self.call(raw:, changes:)
      new(raw:, changes:).call
    end

    def initialize(raw:, changes:)
      @raw = raw
      @changes = changes.sort_by(&:position)
    end

    def call
      cursor = 0
      parts = []

      @changes.each do |change|
        start_offset = change.start_offset
        before_text = change.before_text

        raise MismatchError, "Change offsets overlap" if start_offset < cursor

        current_text = @raw.slice(start_offset, before_text.length) || ""
        raise MismatchError, "Change no longer matches base post" if current_text != before_text

        parts << (@raw.slice(cursor, start_offset - cursor) || "")
        parts << change.after_text
        cursor = start_offset + before_text.length
      end

      parts << (@raw.slice(cursor, @raw.length - cursor) || "")
      parts.join
    end
  end
end
