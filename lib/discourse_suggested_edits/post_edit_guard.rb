# frozen_string_literal: true

module DiscourseSuggestedEdits
  module PostEditGuard
    THREAD_KEY = :discourse_suggested_edits_suppressed_post_edits

    module_function

    def suppress(post_id)
      previous_ids = Thread.current[THREAD_KEY]
      Thread.current[THREAD_KEY] = Array(previous_ids).dup << post_id

      yield
    ensure
      Thread.current[THREAD_KEY] = previous_ids
    end

    def suppressed?(post_id)
      Array(Thread.current[THREAD_KEY]).include?(post_id)
    end
  end
end
