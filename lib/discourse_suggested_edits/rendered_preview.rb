# frozen_string_literal: true

module DiscourseSuggestedEdits
  class RenderedPreview
    UNAVAILABLE_POST_CHANGED = "post_changed"
    UNAVAILABLE_UNSUPPORTED_POST = "unsupported_post"
    UNAVAILABLE_TOO_COMPLEX = "too_complex"
    UNAVAILABLE_NOT_PENDING = "not_pending"
    UNAVAILABLE_NO_VISIBLE_CHANGE = "no_visible_change"

    MAX_CANDIDATE_COOKS = 10
    MAX_RAW_BYTES = 128 * 1024

    TEXT_PHRASING_TAGS = %w[
      a
      abbr
      b
      bdi
      bdo
      cite
      code
      del
      dfn
      em
      i
      ins
      kbd
      mark
      q
      s
      samp
      small
      span
      strong
      sub
      sup
      time
      u
      var
    ].freeze

    IFRAME_TAG_PATTERN = /<iframe/i
    RUN_GAP = '<div class="suggested-edit-preview__gap" aria-hidden="true">…</div>'

    def self.call(suggested_edit)
      new(suggested_edit).call
    end

    def initialize(suggested_edit)
      @suggested_edit = suggested_edit
      @post = suggested_edit.post
    end

    def call
      return unavailable(UNAVAILABLE_POST_CHANGED) if @post.blank?
      if @post.cook_method != Post.cook_methods[:regular]
        return unavailable(UNAVAILABLE_UNSUPPORTED_POST)
      end
      return unavailable(UNAVAILABLE_NOT_PENDING) if resolved?
      return unavailable(UNAVAILABLE_POST_CHANGED) if !base_is_current_post?

      @raw_bytes = @post.raw.bytesize
      @candidate_cooks = 0
      @block_coverage = {}
      @budget_exhausted = @raw_bytes > MAX_RAW_BYTES
      previous = cook(@post.raw, editor_id: @post.last_editor_id) unless @budget_exhausted
      previous_blocks = html_blocks(previous) if previous

      changes = @suggested_edit.edit_changes.to_a
      previews =
        changes.map { |change| { id: change.id }.merge(change_preview(change, previous_blocks)) }

      { available: true, changes: previews, gaps: context_gaps(changes, previous_blocks) }
    end

    private

    def resolved?
      @suggested_edit.applied? || @suggested_edit.dismissed? || @suggested_edit.withdrawn?
    end

    # A grace-period edit can change the raw without bumping the version, so the
    # stored hunks must rebuild the suggestion exactly from the current raw.
    def base_is_current_post?
      return false if !@suggested_edit.pending?
      return false if @post.version != @suggested_edit.base_post_version

      ChangeApplier.call(raw: @post.raw, changes: @suggested_edit.edit_changes.to_a) ==
        @suggested_edit.raw_suggestion
    rescue ChangeApplier::MismatchError
      false
    end

    def change_preview(change, previous_blocks)
      if previous_blocks.nil? || @budget_exhausted || @candidate_cooks >= MAX_CANDIDATE_COOKS
        return unavailable(UNAVAILABLE_TOO_COMPLEX)
      end

      candidate = ChangeApplier.call(raw: @post.raw, changes: [change])
      if @raw_bytes + candidate.bytesize > MAX_RAW_BYTES
        @budget_exhausted = true
        return unavailable(UNAVAILABLE_TOO_COMPLEX)
      end

      @raw_bytes += candidate.bytesize
      @candidate_cooks += 1
      # Applying revises as the suggester; the base keeps the published editor's permissions.
      current = cook(candidate, editor_id: @suggested_edit.user_id)
      return unavailable(UNAVAILABLE_TOO_COMPLEX) if current.nil?

      rendered_diff(previous_blocks, html_blocks(current), change.id)
    rescue ONPDiff::DiffLimitExceeded
      unavailable(UNAVAILABLE_TOO_COMPLEX)
    end

    def html_blocks(html)
      fragment = Nokogiri::HTML5.fragment(html)
      fragment
        .children
        .reject(&:comment?)
        .chunk { |node| node.text? || (node.element? && TEXT_PHRASING_TAGS.include?(node.name)) }
        .flat_map do |phrasing, nodes|
          if phrasing && nodes.any? { |node| node.text? && node.text.present? }
            # The core diff reparses elements only; keep bare text and its inline context together.
            paragraph = fragment.document.create_element("p")
            nodes.each { |node| paragraph << node.dup }
            [paragraph.to_html]
          else
            nodes.filter_map { |node| node.to_html if node.element? }
          end
        end
    end

    def rendered_diff(previous_blocks, current_blocks, change_id)
      operations = ONPDiff.new(previous_blocks, current_blocks).paragraph_diff
      runs = changed_runs(operations)
      return unavailable(UNAVAILABLE_NO_VISIBLE_CHANGE) if runs.empty?

      inline, previous, current = [], [], []
      runs.each do |run|
        blocks = run[:blocks]
        before = blocks.filter_map { |html, operation| html if operation == :delete }.join
        after = blocks.filter_map { |html, operation| html if operation == :add }.join
        diff = DiscourseDiff.new(before, after)
        inline << Nokogiri::HTML5.fragment(diff.inline_html).children.first.inner_html
        sides = Nokogiri::HTML5.fragment(diff.side_by_side_html).children
        previous << sides[0].inner_html
        current << sides[1].inner_html
      end

      @block_coverage[change_id] = runs.sole if runs.one?

      {
        available: true,
        inline: "<div class=\"inline-diff\">#{inline.join(RUN_GAP)}</div>",
        side_by_side:
          "<div class=\"revision-content --previous\">#{previous.join(RUN_GAP)}</div>" \
            "<div class=\"revision-content --current\">#{current.join(RUN_GAP)}</div>",
      }
    end

    def changed_runs(operations)
      position = 0
      operations
        .chunk { |_, operation| operation != :common }
        .filter_map do |changed, blocks|
          start = position
          consumed_positions, insertion_anchors = [], []
          blocks.each do |_, operation|
            if operation == :add
              insertion_anchors << position
            else
              consumed_positions << position if operation == :delete
              position += 1
            end
          end
          next if !changed

          {
            blocks: blocks,
            start: start,
            finish: position,
            consumed_positions: consumed_positions,
            insertion_anchors: insertion_anchors,
          }
        end
    end

    def context_gaps(changes, previous_blocks)
      return [] if changes.empty?

      coverage = changes.map { |change| @block_coverage[change.id] }
      safe_coverage =
        previous_blocks && coverage.none?(&:nil?) &&
          coverage
            .each_cons(2)
            .all? { |left, right| left[:start] <= right[:start] && left[:finish] <= right[:finish] }

      [nil, *changes, nil].each_cons(2)
        .filter_map do |after, before|
          start = after ? after.start_offset + after.before_text.length : 0
          finish = before ? before.start_offset : @post.raw.length
          raw = @post.raw.slice(start, finish - start)
          next if raw.blank?

          gap = {
            id: "#{after&.id || "start"}-#{before&.id || "end"}",
            before_change_id: before&.id,
            after_change_id: after&.id,
            raw: raw,
          }
          if safe_coverage
            first = after ? @block_coverage.fetch(after.id)[:finish] : 0
            last = before ? @block_coverage.fetch(before.id)[:start] : previous_blocks.length
            html = context_html(previous_blocks, coverage, first, last)
            gap[:html] = html if html.present?
          end
          gap
        end
    end

    def context_html(previous_blocks, coverage, first, last)
      return if first >= last
      # Every card matters: even a distant hunk can display this base block.
      if coverage.any? { |run|
           run[:consumed_positions].any? { |position| position >= first && position < last } ||
             run[:insertion_anchors].any? { |position| position > first && position < last }
         }
        return
      end

      previous_blocks[first...last].join
    end

    def cook(raw, editor_id:)
      neutralize_embeds(cooking_post(editor_id).cook(raw, cooking_options))
    rescue URI::InvalidURIError => e
      # Secure-upload rewriting parses stored cooked URLs; malformed ones are
      # not worth failing an optional preview over, so fall back to source.
      Discourse.warn_exception(
        e,
        message: "Failed to cook rendered preview for suggested edit #{@suggested_edit.id}",
      )
      nil
    end

    def cooking_post(editor_id)
      @post.dup.tap do |post|
        post.id = @post.id
        post.last_editor_id = editor_id
        post.readonly!
      end
    end

    def cooking_options
      (@post.cooking_options || {}).symbolize_keys.merge(topic_id: @post.topic_id)
    end

    def neutralize_embeds(html)
      return html if !html.match?(IFRAME_TAG_PATTERN)

      fragment = Nokogiri::HTML5.fragment(html)
      fragment
        .css("iframe")
        .each do |iframe|
          src = iframe["data-original-href"].presence || iframe["src"].presence
          if src.blank?
            iframe.remove
            next
          end

          anchor = fragment.document.create_element("a", src, href: src)
          if iframe.parent&.name == "p"
            iframe.replace(anchor)
          else
            paragraph = fragment.document.create_element("p")
            paragraph << anchor
            iframe.replace(paragraph)
          end
        end

      fragment.to_html
    end

    def unavailable(reason)
      { available: false, unavailable_reason: reason }
    end
  end
end
