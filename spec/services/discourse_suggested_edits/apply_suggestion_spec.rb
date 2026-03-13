# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::ApplySuggestion do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:suggestion_id) }

    it "requires accepted_change_ids to be an array" do
      contract = described_class.new(suggestion_id: 1, accepted_change_ids: "1")
      expect(contract).not_to be_valid
      expect(contract.errors[:accepted_change_ids]).to include(
        I18n.t("discourse_suggested_edits.errors.invalid_selected_changes"),
      )
    end
  end

  describe ".call" do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:suggest_group, :group)
    fab!(:review_group, :group)
    fab!(:category)
    fab!(:suggester) { Fabricate(:user, groups: [suggest_group]) }
    fab!(:reviewer) { Fabricate(:user, groups: [review_group]) }
    fab!(:outsider, :user)
    fab!(:topic) { Fabricate(:topic, category: category) }
    fab!(:post) do
      Fabricate(:post, topic: topic, post_number: 1, raw: "Line one\nLine two\nLine three\n")
    end
    fab!(:suggestion) do
      Fabricate(
        :suggested_edit,
        post: post,
        user: suggester,
        raw_suggestion: "Line one\nLine TWO\nLine three\n",
        base_post_version: post.version,
      )
    end

    let(:params) { { suggestion_id:, accepted_change_ids: } }
    let(:dependencies) { { guardian: acting_user.guardian } }
    let(:acting_user) { reviewer }
    let(:suggestion_id) { suggestion.id }
    let(:accepted_change_ids) { suggestion.edit_changes.pluck(:id) }

    before do
      SiteSetting.suggested_edits_enabled = true
      SiteSetting.suggested_edits_suggest_groups = suggest_group.id.to_s
      SiteSetting.suggested_edits_review_groups = review_group.id.to_s
      SiteSetting.suggested_edits_included_categories = category.id.to_s

      DiscourseSuggestedEdits::ChangeExtractor
        .call(original_raw: post.raw, new_raw: suggestion.raw_suggestion)
        .each { |change| Fabricate(:suggested_edit_change, suggested_edit: suggestion, **change) }
    end

    context "when contract is invalid" do
      let(:suggestion_id) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when accepted_change_ids is not an array" do
      let(:accepted_change_ids) { "1" }

      it { is_expected.to fail_a_contract }
    end

    context "when suggestion is not found" do
      let(:suggestion_id) { 0 }

      it { is_expected.to fail_to_find_a_model(:suggested_edit) }
    end

    context "when user cannot review suggestions" do
      let(:acting_user) { outsider }

      it { is_expected.to fail_a_policy(:can_review_suggested_edit) }
    end

    context "when no accepted changes are selected" do
      let(:accepted_change_ids) { [] }

      it { is_expected.to fail_a_step(:apply_changes) }
    end

    context "when accepted_change_ids includes unknown ids" do
      let(:accepted_change_ids) { suggestion.edit_changes.pluck(:id) + [999_999] }

      it { is_expected.to fail_a_step(:apply_changes) }
    end

    context "when suggestion is stale" do
      before { post.update_column(:version, post.version + 1) }

      it { is_expected.to fail_a_step(:apply_changes) }

      it "marks suggestion as stale" do
        result
        expect(suggestion.reload).to be_stale
      end
    end

    context "when suggestion is no longer pending" do
      before { suggestion.update!(status: :dismissed) }

      it { is_expected.to fail_a_step(:apply_changes) }
    end

    context "when everything is valid" do
      let(:messages) { MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") { result } }

      it { is_expected.to run_successfully }

      it "applies the selected changes and marks suggestion applied" do
        expect { result }.to change { post.reload.raw }.to("Line one\nLine TWO\nLine three")
        expect(suggestion.reload).to be_applied
        expect(suggestion.applied_by_id).to eq(reviewer.id)
        expect(suggestion.applied_at).to be_present
      end

      it "publishes review and resolved updates" do
        messages
        review_message = messages.find { |m| m.data[:type] == "suggested_edits_changed" }
        resolved_message = messages.find { |m| m.data[:type] == "suggested_edit_resolved" }

        expect(review_message.data[:pending_count]).to eq(0)
        expect(resolved_message.user_ids).to eq([suggester.id])
      end
    end
  end
end
