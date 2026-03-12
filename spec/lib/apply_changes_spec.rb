# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::ApplySuggestion do
  fab!(:suggest_group, :group)
  fab!(:review_group, :group)
  fab!(:category)
  fab!(:user) { Fabricate(:user, groups: [suggest_group]) }
  fab!(:reviewer) { Fabricate(:user, groups: [review_group]) }
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:post) do
    Fabricate(:post, topic: topic, post_number: 1, raw: "Line one\nLine two\nLine three\n")
  end

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_suggest_group = suggest_group.id.to_s
    SiteSetting.suggested_edits_review_group = review_group.id.to_s
    SiteSetting.suggested_edits_included_categories = category.id.to_s
  end

  def create_suggestion(raw:)
    result =
      DiscourseSuggestedEdits::CreateSuggestion.call(
        guardian: Guardian.new(user),
        params: {
          post_id: post.id,
          raw: raw,
        },
      )

    expect(result).to be_success
    result.suggested_edit
  end

  def apply_suggestion(suggestion, accepted_change_ids)
    described_class.call(
      guardian: Guardian.new(reviewer),
      params: {
        suggestion_id: suggestion.id,
        accepted_change_ids: accepted_change_ids,
      },
    )
  end

  describe ".call" do
    it "applies accepted changes and creates a revision" do
      suggestion = create_suggestion(raw: "Line one\nLine TWO\nLine three\n")

      result = apply_suggestion(suggestion, suggestion.edit_changes.pluck(:id))

      expect(result).to be_success
      expect(post.reload.raw).to include("Line TWO")
      expect(suggestion.reload).to be_applied
      expect(suggestion.applied_by_id).to eq(reviewer.id)
      expect(suggestion.applied_at).to be_present
    end

    it "only applies accepted changes, leaving rejected ones" do
      suggestion = create_suggestion(raw: "Line ONE\nLine two\nLine THREE\n")
      first_change = suggestion.edit_changes.first

      result = apply_suggestion(suggestion, [first_change.id])

      expect(result).to be_success
      expect(post.reload.raw).to eq("Line ONE\nLine two\nLine three")
    end

    it "applies the intended repeated segment using stored offsets" do
      post.update!(raw: "Repeat\nMiddle\nRepeat\n")
      suggestion = create_suggestion(raw: "Repeat\nMiddle\nChanged\n")

      result = apply_suggestion(suggestion, suggestion.edit_changes.pluck(:id))

      expect(result).to be_success
      expect(post.reload.raw).to eq("Repeat\nMiddle\nChanged")
    end

    it "marks other pending suggestions stale after applying a change" do
      suggestion = create_suggestion(raw: "Line one\nLine TWO\nLine three\n")
      other_user = Fabricate(:user, groups: [suggest_group])
      other_result =
        DiscourseSuggestedEdits::CreateSuggestion.call(
          guardian: Guardian.new(other_user),
          params: {
            post_id: post.id,
            raw: "Line one\nLine two\nLine THREE\n",
          },
        )

      expect(other_result).to be_success

      result = apply_suggestion(suggestion, suggestion.edit_changes.pluck(:id))

      expect(result).to be_success
      expect(other_result.suggested_edit.reload).to be_stale
    end

    it "rejects empty accepted change ids" do
      suggestion = create_suggestion(raw: "Line one\nLine TWO\nLine three\n")

      result = apply_suggestion(suggestion, [])

      expect(result).to be_failure
      expect(result["result.step.apply_changes"].error).to eq(
        I18n.t("discourse_suggested_edits.errors.no_selected_changes"),
      )
      expect(suggestion.reload).to be_pending
    end

    it "rejects invalid change ids" do
      suggestion = create_suggestion(raw: "Line one\nLine TWO\nLine three\n")

      result = apply_suggestion(suggestion, [suggestion.edit_changes.first.id, 999_999])

      expect(result).to be_failure
      expect(result["result.step.apply_changes"].error).to eq(
        I18n.t("discourse_suggested_edits.errors.invalid_selected_changes"),
      )
      expect(suggestion.reload).to be_pending
    end

    it "marks the suggestion stale when the post version has changed" do
      suggestion = create_suggestion(raw: "Line one\nLine TWO\nLine three\n")
      post.update_column(:version, post.version + 1)

      result = apply_suggestion(suggestion, suggestion.edit_changes.pluck(:id))

      expect(result).to be_failure
      expect(result["result.step.apply_changes"].error).to eq(
        I18n.t("discourse_suggested_edits.errors.stale"),
      )
      expect(suggestion.reload).to be_stale
    end

    it "rejects suggestions that are no longer pending" do
      suggestion = create_suggestion(raw: "Line one\nLine TWO\nLine three\n")
      suggestion.update!(status: :dismissed)

      result = apply_suggestion(suggestion, suggestion.edit_changes.pluck(:id))

      expect(result).to be_failure
      expect(result["result.step.apply_changes"].error).to eq(
        I18n.t("discourse_suggested_edits.errors.not_pending"),
      )
    end
  end
end
