# frozen_string_literal: true

RSpec.describe "Suggested Edits", type: :system do
  fab!(:admin)
  fab!(:category)
  fab!(:suggest_group, :group)
  fab!(:review_group, :group)
  fab!(:suggester) { Fabricate(:user, groups: [suggest_group]) }
  fab!(:reviewer) { Fabricate(:user, groups: [review_group]) }
  fab!(:topic_author) { Fabricate(:user, refresh_auto_groups: true) }
  fab!(:first_post) do
    create_post(user: topic_author, category: category, raw: "Original post content here.")
  end
  fab!(:topic) { first_post.topic }
  fab!(:reply_post) { create_post(topic: topic, raw: "This is a reply.") }

  let(:suggested_edits_page) { PageObjects::Pages::SuggestedEdits.new }
  let(:topic_page) { PageObjects::Pages::Topic.new }

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_suggest_group = suggest_group.id.to_s
    SiteSetting.suggested_edits_review_group = review_group.id.to_s
    SiteSetting.suggested_edits_included_categories = category.id.to_s
  end

  context "when suggesting an edit" do
    before { sign_in(suggester) }

    it "shows suggest edit button on first post" do
      visit "/t/#{topic.slug}/#{topic.id}"
      expect(suggested_edits_page).to have_suggest_edit_button(first_post)
    end

    it "allows creating a suggestion" do
      visit "/t/#{topic.slug}/#{topic.id}"
      suggested_edits_page.click_suggest_edit(first_post)

      expect(suggested_edits_page).to have_composer_open

      suggested_edits_page.fill_composer("Updated post content here.")
      suggested_edits_page.submit_suggestion

      expect(suggested_edits_page).to have_no_composer
      expect(page).to have_css(".fk-d-toasts", text: /suggested/i)
    end
  end

  context "when reviewing a suggestion" do
    fab!(:suggested_edit) do
      Fabricate(
        :suggested_edit,
        post: first_post,
        user: suggester,
        raw_suggestion: "Updated post content here.",
        base_post_version: first_post.version,
      )
    end

    fab!(:change1) do
      Fabricate(
        :suggested_edit_change,
        suggested_edit: suggested_edit,
        position: 0,
        start_offset: 0,
        before_text: "Original post content here.",
        after_text: "Updated post content here.",
      )
    end

    context "as a reviewer" do
      before { sign_in(reviewer) }

      it "shows review banner and allows accepting changes" do
        visit "/t/#{topic.slug}/#{topic.id}"

        expect(suggested_edits_page).to have_review_banner
        suggested_edits_page.click_review

        expect(suggested_edits_page).to have_review_modal
        expect(suggested_edits_page.change_items.length).to eq(1)

        suggested_edits_page.accept_all
        suggested_edits_page.apply_accepted

        expect(suggested_edits_page).to have_no_review_modal
        expect(first_post.reload.raw).to eq("Updated post content here.")
      end

      it "allows dismissing a suggestion" do
        visit "/t/#{topic.slug}/#{topic.id}"

        suggested_edits_page.click_review
        suggested_edits_page.dismiss_suggestion

        expect(suggested_edits_page).to have_no_review_modal
        expect(suggested_edit.reload.status).to eq("dismissed")
      end
    end

    context "as the post author" do
      before { sign_in(topic_author) }

      it "shows review banner to the post author" do
        visit "/t/#{topic.slug}/#{topic.id}"
        expect(suggested_edits_page).to have_review_banner
      end
    end
  end

  context "when the user has a pending suggestion" do
    fab!(:suggested_edit) do
      Fabricate(
        :suggested_edit,
        post: first_post,
        user: suggester,
        raw_suggestion: "Updated post content here.",
        base_post_version: first_post.version,
      )
    end

    before { sign_in(suggester) }

    it "shows own pending banner" do
      visit "/t/#{topic.slug}/#{topic.id}"
      expect(suggested_edits_page).to have_own_banner
    end

    it "allows withdrawing a suggestion" do
      suggestion_id = suggested_edit.id
      visit "/t/#{topic.slug}/#{topic.id}"

      suggested_edits_page.click_own_banner_withdraw
      page.find(".dialog-footer .btn-primary").click

      expect(suggested_edits_page).to have_no_own_banner
      expect(SuggestedEdit.find(suggestion_id)).to be_withdrawn
    end

    it "hides own banner after suggestion is applied" do
      Fabricate(
        :suggested_edit_change,
        suggested_edit: suggested_edit,
        position: 0,
        start_offset: 0,
        before_text: "Original post content here.",
        after_text: "Updated post content here.",
      )

      visit "/t/#{topic.slug}/#{topic.id}"
      expect(suggested_edits_page).to have_own_banner

      DiscourseSuggestedEdits::ApplySuggestion.call(
        guardian: Guardian.new(reviewer),
        params: {
          suggestion_id: suggested_edit.id,
          accepted_change_ids: suggested_edit.edit_changes.pluck(:id),
        },
      )

      visit "/t/#{topic.slug}/#{topic.id}"
      expect(suggested_edits_page).to have_no_own_banner
    end
  end

  context "when another suggester is viewing the topic" do
    fab!(:other_suggester) { Fabricate(:user, groups: [suggest_group]) }

    before { sign_in(other_suggester) }

    it "does not show the review banner when another user's suggestion is created" do
      visit "/t/#{topic.slug}/#{topic.id}"
      expect(suggested_edits_page).to have_no_review_banner

      DiscourseSuggestedEdits::CreateSuggestion.call(
        guardian: Guardian.new(suggester),
        params: {
          post_id: first_post.id,
          raw: "Updated post content here.",
        },
      )

      expect(suggested_edits_page).to have_no_review_banner
    end
  end

  context "when clicking suggest edit with an existing pending suggestion" do
    fab!(:suggested_edit) do
      Fabricate(
        :suggested_edit,
        post: first_post,
        user: suggester,
        raw_suggestion: "My pending suggestion text.",
        base_post_version: first_post.version,
      )
    end

    before { sign_in(suggester) }

    it "opens the existing suggestion in the composer" do
      visit "/t/#{topic.slug}/#{topic.id}"

      suggested_edits_page.click_suggest_edit(first_post)
      expect(suggested_edits_page).to have_composer_open
      expect(suggested_edits_page.composer_value).to eq("My pending suggestion text.")
    end
  end

  context "when creating and then editing a suggestion" do
    before { sign_in(suggester) }

    it "allows creating then revising without draft modals" do
      visit "/t/#{topic.slug}/#{topic.id}"

      suggested_edits_page.click_suggest_edit(first_post)
      expect(suggested_edits_page).to have_composer_open
      suggested_edits_page.fill_composer("First suggested change.")
      suggested_edits_page.submit_suggestion

      expect(suggested_edits_page).to have_no_composer
      expect(page).to have_css(".fk-d-toasts", text: /suggested/i)

      expect(suggested_edits_page).to have_own_banner
      expect(suggested_edits_page).to have_no_discard_draft_modal

      suggested_edits_page.click_own_banner_edit
      expect(suggested_edits_page).to have_composer_open
      expect(suggested_edits_page).to have_no_discard_draft_modal

      suggested_edits_page.fill_composer("Revised suggested change.")
      suggested_edits_page.submit_suggestion

      expect(suggested_edits_page).to have_no_composer
      expect(page).to have_css(".fk-d-toasts", text: /updated/i)
      expect(suggested_edits_page).to have_no_discard_draft_modal

      suggestion = SuggestedEdit.last
      expect(suggestion.raw_suggestion).to eq("Revised suggested change.")
    end
  end

  context "when editing a suggestion with rich editor" do
    fab!(:suggested_edit) do
      Fabricate(
        :suggested_edit,
        post: first_post,
        user: suggester,
        raw_suggestion: "Updated post content here.",
        base_post_version: first_post.version,
      )
    end

    before do
      SiteSetting.rich_editor = true
      suggester.user_option.update!(composition_mode: UserOption.composition_mode_types[:rich])
      sign_in(suggester)
    end

    it "highlights changed text when opening existing suggestion" do
      visit "/t/#{topic.slug}/#{topic.id}"

      suggested_edits_page.click_suggest_edit(first_post)
      expect(suggested_edits_page).to have_composer_open

      # Verify the ProseMirror editor is active (not textarea)
      expect(page).to have_css("#reply-control .ProseMirror")

      expect(suggested_edits_page).to have_changed_block_markers
      expect(suggested_edits_page).to have_changed_text_markers
    end

    it "highlights changed text when opening an existing suggestion from the own banner" do
      visit "/t/#{topic.slug}/#{topic.id}"

      expect(suggested_edits_page).to have_own_banner
      suggested_edits_page.click_own_banner_edit
      expect(suggested_edits_page).to have_composer_open
      expect(page).to have_css("#reply-control .ProseMirror")

      expect(suggested_edits_page).to have_changed_block_markers
      expect(suggested_edits_page).to have_changed_text_markers
    end

    it "shows no markers when opening fresh suggestion with no changes" do
      SuggestedEdit.destroy_all
      visit "/t/#{topic.slug}/#{topic.id}"

      suggested_edits_page.click_suggest_edit(first_post)
      expect(suggested_edits_page).to have_composer_open
      expect(page).to have_css("#reply-control .ProseMirror")
      expect(suggested_edits_page).to have_no_changed_block_markers
    end
  end

  context "when user is not in suggest group" do
    fab!(:outsider, :user)

    before { sign_in(outsider) }

    it "does not show suggest edit button" do
      visit "/t/#{topic.slug}/#{topic.id}"
      expect(suggested_edits_page).to have_no_suggest_edit_button(first_post)
    end
  end
end
