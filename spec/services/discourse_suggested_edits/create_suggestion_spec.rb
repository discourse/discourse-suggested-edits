# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::CreateSuggestion do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:post_id) }
    it { is_expected.to validate_presence_of(:raw) }
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:suggest_group, :group)
    fab!(:review_group, :group)
    fab!(:category)
    fab!(:tag)
    fab!(:acting_user) { Fabricate(:user, groups: [suggest_group]) }
    fab!(:topic) { Fabricate(:topic, category: category, tags: [tag]) }
    fab!(:post) do
      Fabricate(:post, topic: topic, post_number: 1, raw: "Line one\nLine two\nLine three\n")
    end

    let(:params) { { post_id:, raw:, reason: } }
    let(:dependencies) { { guardian: acting_user.guardian } }
    let(:post_id) { post.id }
    let(:raw) { "Line one\nLine TWO\nLine three\n" }
    let(:reason) { "Fixed typo" }

    before do
      SiteSetting.suggested_edits_enabled = true
      SiteSetting.suggested_edits_suggest_groups = suggest_group.id.to_s
      SiteSetting.suggested_edits_review_groups = review_group.id.to_s
      SiteSetting.suggested_edits_included_categories = category.id.to_s
    end

    context "when contract is invalid" do
      let(:raw) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when post is not found" do
      let(:post_id) { 0 }

      it { is_expected.to fail_to_find_a_model(:post) }
    end

    context "when user cannot suggest edits" do
      fab!(:acting_user, :user)

      it { is_expected.to fail_a_policy(:can_suggest_edit) }
    end

    context "when payload validation fails" do
      let(:raw) { "a" * (SiteSetting.max_post_length + 1) }

      it { is_expected.to fail_a_step(:validate_payload) }
    end

    context "when raw is unchanged" do
      let(:raw) { post.raw }

      it { is_expected.to fail_a_step(:ensure_raw_changed) }
    end

    context "when user already has a pending suggestion for the post" do
      before do
        Fabricate(
          :suggested_edit,
          post: post,
          user: acting_user,
          raw_suggestion: "Line one\nLine two\nLine THREE\n",
          base_post_version: post.version,
        )
      end

      it { is_expected.to fail_a_step(:ensure_no_pending_suggestion) }
    end

    context "when everything is valid" do
      let(:messages) { MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") { result } }

      it { is_expected.to run_successfully }

      it "creates a pending suggestion with extracted changes" do
        expect { result }.to change { SuggestedEdit.pending.count }.by(1)
        expect(result.suggested_edit.raw_suggestion).to eq(raw)
        expect(result.suggested_edit.reason).to eq(reason)
        expect(result.suggested_edit.edit_changes.count).to eq(1)
      end

      it "publishes review updates" do
        messages
        review_message = messages.find { |m| m.data[:type] == "suggested_edits_changed" }

        expect(review_message.data[:pending_count]).to eq(1)
        expect(review_message.user_ids).to eq([post.user_id])
        expect(review_message.group_ids).to contain_exactly(
          review_group.id,
          Group::AUTO_GROUPS[:admins],
        )
      end
    end
  end
end
