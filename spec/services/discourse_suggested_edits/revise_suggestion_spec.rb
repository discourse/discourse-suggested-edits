# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::ReviseSuggestion do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:suggestion_id) }
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
    fab!(:suggested_edit) do
      Fabricate(
        :suggested_edit,
        post: post,
        user: acting_user,
        raw_suggestion: "Line one\nLine TWO\nLine three\n",
        base_post_version: post.version,
        reason: "Original reason",
      )
    end

    let(:params) { { suggestion_id:, raw:, reason: } }
    let(:dependencies) { { guardian: acting_user.guardian } }
    let(:suggestion_id) { suggested_edit.id }
    let(:raw) { "Line ONE\nLine two\nLine THREE\n" }
    let(:reason) { "Reworded" }

    before do
      SiteSetting.suggested_edits_enabled = true
      SiteSetting.suggested_edits_suggest_groups = suggest_group.id.to_s
      SiteSetting.suggested_edits_review_groups = review_group.id.to_s
      SiteSetting.suggested_edits_included_categories = category.id.to_s

      DiscourseSuggestedEdits::ChangeExtractor
        .call(original_raw: post.raw, new_raw: suggested_edit.raw_suggestion)
        .each do |change|
          Fabricate(:suggested_edit_change, suggested_edit: suggested_edit, **change)
        end
    end

    context "when contract is invalid" do
      let(:raw) { nil }

      it { is_expected.to fail_a_contract }
    end

    context "when suggestion is not found" do
      let(:suggestion_id) { 0 }

      it { is_expected.to fail_to_find_a_model(:suggested_edit) }
    end

    context "when user cannot revise the suggestion" do
      fab!(:acting_user, :user)

      it { is_expected.to fail_a_policy(:can_update_suggested_edit) }
    end

    context "when payload validation fails" do
      let(:raw) { "a" * (SiteSetting.max_post_length + 1) }

      it { is_expected.to fail_a_step(:validate_payload) }
    end

    context "when suggestion is no longer pending" do
      before { suggested_edit.update!(status: :dismissed) }

      it { is_expected.to fail_a_step(:ensure_pending) }
    end

    context "when raw is unchanged from the source post" do
      let(:raw) { post.raw }

      it { is_expected.to fail_a_step(:ensure_raw_changed) }
    end

    context "when everything is valid" do
      let(:messages) { MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") { result } }

      it { is_expected.to run_successfully }

      it "replaces suggestion content and changes" do
        expect { result }.to change { suggested_edit.reload.raw_suggestion }.to(raw)
        expect(suggested_edit.reason).to eq(reason)
        expect(suggested_edit.edit_changes.pluck(:position)).to eq([0, 1])
      end

      context "when reason is nil" do
        let(:reason) { nil }

        it "keeps the previous reason" do
          result
          expect(suggested_edit.reload.reason).to eq("Original reason")
        end
      end

      it "publishes review updates" do
        messages
        review_message = messages.find { |m| m.data[:type] == "suggested_edits_changed" }

        expect(review_message.data[:pending_count]).to eq(1)
      end
    end
  end
end
