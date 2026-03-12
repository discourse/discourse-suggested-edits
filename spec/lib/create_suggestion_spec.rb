# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::CreateSuggestion do
  fab!(:suggest_group, :group)
  fab!(:user) { Fabricate(:user, groups: [suggest_group]) }
  fab!(:category)
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:post) do
    Fabricate(:post, topic: topic, post_number: 1, raw: "Line one\nLine two\nLine three\n")
  end

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_suggest_group = suggest_group.id.to_s
    SiteSetting.suggested_edits_included_categories = category.id.to_s
  end

  def call_service(raw:, reason: nil)
    described_class.call(
      guardian: Guardian.new(user),
      params: {
        post_id: post.id,
        raw: raw,
        reason: reason,
      },
    )
  end

  describe ".call" do
    it "creates a suggested edit with stored changes" do
      result = call_service(raw: "Line one\nLine TWO\nLine three\n", reason: "Fixed typo")

      expect(result).to be_success
      expect(result.suggested_edit).to be_pending
      expect(result.suggested_edit.raw_suggestion).to eq("Line one\nLine TWO\nLine three\n")
      expect(result.suggested_edit.base_post_version).to eq(post.version)
      expect(result.suggested_edit.reason).to eq("Fixed typo")
      expect(result.suggested_edit.edit_changes.count).to eq(1)
      expect(result.suggested_edit.edit_changes.first.start_offset).to eq("Line one\n".length)
    end

    it "stores multiple changes in base-order" do
      result = call_service(raw: "Line ONE\nLine two\nLine THREE\n")

      expect(result).to be_success
      expect(result.suggested_edit.edit_changes.pluck(:position)).to eq([0, 1])
      expect(result.suggested_edit.edit_changes.pluck(:start_offset)).to eq(
        [0, "Line one\nLine two\n".length],
      )
    end

    it "supports pure additions" do
      result = call_service(raw: "Line one\nLine two\nLine three\nLine four\n")

      expect(result).to be_success
      expect(result.suggested_edit.edit_changes.last.before_text).to eq("")
      expect(result.suggested_edit.edit_changes.last.after_text).to eq("Line four\n")
      expect(result.suggested_edit.edit_changes.last.start_offset).to eq(post.raw.length)
    end

    it "rejects duplicate pending suggestions for the same user and post" do
      call_service(raw: "Line one\nLine TWO\nLine three\n")
      result = call_service(raw: "Line one\nLine two\nLine THREE\n")

      expect(result).to be_failure
      expect(result["result.step.ensure_no_pending_suggestion"].error).to eq(
        I18n.t("discourse_suggested_edits.errors.already_pending"),
      )
    end
  end
end
