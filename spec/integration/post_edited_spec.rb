# frozen_string_literal: true

RSpec.describe "Suggested edits post edit hook" do
  fab!(:editor, :admin)
  fab!(:suggester, :user)
  fab!(:post) { Fabricate(:post, raw: "Original content here.\n") }

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.editing_grace_period = 0
  end

  def create_suggestion
    raw = "Suggested content here.\n"
    suggestion =
      Fabricate(
        :suggested_edit,
        post: post,
        user: suggester,
        raw_suggestion: raw,
        base_post_version: post.version,
      )

    DiscourseSuggestedEdits::ChangeExtractor
      .call(original_raw: post.raw, new_raw: raw)
      .each { |change| suggestion.edit_changes.create!(change) }

    suggestion.reload
  end

  it "marks outdated suggestions stale and bumps their updated_at" do
    suggestion = create_suggestion
    suggestion.update_column(:updated_at, 1.hour.ago)
    original_updated_at = suggestion.updated_at

    PostRevisor.new(post, post.topic).revise!(editor, raw: "Revised content here.\n")
    suggestion.reload

    expect(post.reload.version).to be > suggestion.base_post_version
    expect(suggestion).to be_stale
    expect(suggestion.updated_at).to be > original_updated_at
  end
end
