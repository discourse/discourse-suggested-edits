# frozen_string_literal: true

module DiscourseSuggestedEdits
  class ChangeExtractor
    def self.call(original_raw:, new_raw:)
      new(original_raw:, new_raw:).call
    end

    def initialize(original_raw:, new_raw:)
      @original_raw = original_raw
      @new_raw = new_raw
    end

    def call
      diff_result = ONPDiff.new(@original_raw.lines, @new_raw.lines).short_diff

      original_offset = 0
      current_start_offset = nil
      current_before = []
      current_after = []
      hunks = []

      flush =
        lambda do
          next if current_start_offset.nil?

          hunks << {
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

      hunks.each_with_index.map { |hunk, index| hunk.merge(position: index) }
    end
  end
end
