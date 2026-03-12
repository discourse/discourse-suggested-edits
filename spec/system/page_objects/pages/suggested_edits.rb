# frozen_string_literal: true

module PageObjects
  module Pages
    class SuggestedEdits < PageObjects::Pages::Base
      def click_suggest_edit(post)
        within_post(post) { find(".post-action-menu__suggest-edit").click }
      end

      def has_suggest_edit_button?(post)
        within_post(post) { has_css?(".post-action-menu__suggest-edit") }
      end

      def has_no_suggest_edit_button?(post)
        within_post(post) { has_no_css?(".post-action-menu__suggest-edit") }
      end

      def has_composer_open?
        has_css?("#reply-control .d-editor-input")
      end

      def has_no_composer?
        has_no_css?("#reply-control .d-editor-input")
      end

      def fill_composer(content)
        find("#reply-control .d-editor-input").fill_in(with: content)
      end

      def submit_suggestion
        find("#reply-control .save-or-cancel .create").click
      end

      def has_review_banner?
        has_css?(".suggested-edits-banner--review")
      end

      def has_no_review_banner?
        has_no_css?(".suggested-edits-banner--review")
      end

      def click_review
        find(".suggested-edits-banner--review .btn-primary").click
      end

      def has_review_modal?
        has_css?(".suggested-edits-review-modal")
      end

      def has_no_review_modal?
        has_no_css?(".suggested-edits-review-modal")
      end

      def accept_change(index)
        all(".suggested-edit-change-item__accept")[index].click
      end

      def reject_change(index)
        all(".suggested-edit-change-item__reject")[index].click
      end

      def accept_all
        find(".suggested-edits-review-modal .btn-default", text: /Accept All/i).click
      end

      def apply_accepted
        find(".suggested-edits-review-modal .btn-primary").click
      end

      def dismiss_suggestion
        find(".suggested-edits-review-modal .btn-danger").click
      end

      def has_own_banner?
        has_css?(".suggested-edits-banner--own")
      end

      def has_no_own_banner?
        has_no_css?(".suggested-edits-banner--own")
      end

      def click_own_banner_edit
        find(".suggested-edits-banner--own .btn-default").click
      end

      def click_own_banner_withdraw
        find(".suggested-edits-banner--own .btn-danger").click
      end

      def composer_value
        find("#reply-control .d-editor-input").value
      end

      def has_discard_draft_modal?
        has_css?(".discard-draft-modal")
      end

      def has_no_discard_draft_modal?
        has_no_css?(".discard-draft-modal")
      end

      def change_items
        all(".suggested-edit-change-item")
      end

      def has_changed_block_markers?
        has_css?("#reply-control .ProseMirror .suggested-edit-changed-block")
      end

      def has_no_changed_block_markers?
        has_no_css?("#reply-control .ProseMirror .suggested-edit-changed-block")
      end

      def has_changed_text_markers?
        has_css?("#reply-control .ProseMirror .suggested-edit-changed-text")
      end

      def has_no_changed_text_markers?
        has_no_css?("#reply-control .ProseMirror .suggested-edit-changed-text")
      end

      private

      def within_post(post)
        post_number = post.is_a?(Post) ? post.post_number : post
        within(".topic-post:not(.staged) #post_#{post_number}") { yield }
      end
    end
  end
end
