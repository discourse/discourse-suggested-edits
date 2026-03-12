# frozen_string_literal: true

class SuggestedEditChangeSerializer < ApplicationSerializer
  PREVIEW_CONTEXT_LENGTH = 90

  attributes :id,
             :position,
             :before_text,
             :after_text,
             :diff_html,
             :preview_context_before,
             :preview_context_after,
             :context_before,
             :context_after

  def diff_html
    object.diff_html
  end

  def preview_context_before
    context_preview[:before]
  end

  def preview_context_after
    context_preview[:after]
  end

  def context_before
    raw_context[:before]
  end

  def context_after
    raw_context[:after]
  end

  private

  def context_preview
    @context_preview ||= {
      before:
        if raw_context[:before].length > PREVIEW_CONTEXT_LENGTH
          raw_context[:before][-PREVIEW_CONTEXT_LENGTH, PREVIEW_CONTEXT_LENGTH]
        else
          raw_context[:before]
        end,
      after: raw_context[:after].first(PREVIEW_CONTEXT_LENGTH),
    }
  end

  def raw_context
    @raw_context ||=
      begin
        post_raw = object.suggested_edit.post&.raw.to_s
        before_text = post_raw[0...object.start_offset].to_s.rstrip
        after_text = post_raw[object.start_offset + object.before_text.length..].to_s.lstrip

        { before: before_text, after: after_text }
      end
  end
end
