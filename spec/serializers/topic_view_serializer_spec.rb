# frozen_string_literal: true

RSpec.describe TopicViewSerializer do
  fab!(:category)
  fab!(:review_group, :group)
  fab!(:reviewer) { Fabricate(:user, groups: [review_group]) }
  fab!(:topic) { Fabricate(:topic, category: category) }
  fab!(:first_post) { Fabricate(:post, topic: topic, post_number: 1) }

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_review_groups = review_group.id.to_s
  end

  describe "pending_suggested_edit_count" do
    it "uses the preloaded review permission when serializing topic view" do
      topic_view = TopicView.new(topic.id, reviewer)
      guardian = topic_view.guardian

      allow(guardian).to receive(:can_review_suggested_edits_for_post?).and_call_original

      payload = described_class.new(topic_view, scope: guardian, root: false).as_json

      expect(payload).to have_key(:pending_suggested_edit_count)
      expect(guardian).not_to have_received(:can_review_suggested_edits_for_post?)
    end
  end
end
