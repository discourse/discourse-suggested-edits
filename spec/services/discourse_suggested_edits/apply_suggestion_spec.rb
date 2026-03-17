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

      it "records the reviewer in the post edit reason" do
        result
        expect(post.reload.edit_reason).to eq(
          I18n.t("discourse_suggested_edits.applied_reason", username: reviewer.username),
        )
      end

      it "publishes review and resolved updates" do
        messages
        review_message = messages.find { |m| m.data[:type] == "suggested_edits_changed" }
        resolved_message = messages.find { |m| m.data[:type] == "suggested_edit_resolved" }

        expect(review_message.data[:pending_count]).to eq(0)
        expect(resolved_message.user_ids).to eq([suggester.id])
      end
    end

    context "with change_overrides" do
      let(:params) { { suggestion_id:, accepted_change_ids:, change_overrides: } }

      context "when overriding an accepted change" do
        let(:change_overrides) { { suggestion.edit_changes.first.id.to_s => "Line CUSTOM\n" } }

        it "applies the overridden text instead of the original after_text" do
          expect { result }.to change { post.reload.raw }.to("Line one\nLine CUSTOM\nLine three")
        end

        it "does not persist the override to the change record" do
          result
          expect(suggestion.edit_changes.first.reload.after_text).to eq("Line TWO\n")
        end
      end

      context "when overriding with an empty string" do
        let(:change_overrides) { { suggestion.edit_changes.first.id.to_s => "" } }

        it "applies the empty string, effectively deleting the original text" do
          expect { result }.to change { post.reload.raw }.to("Line one\nLine three")
        end
      end

      context "when override targets a non-accepted change id" do
        fab!(:multi_post) do
          Fabricate(:post, topic: topic, post_number: 2, raw: "Alpha\nMiddle\nBravo\n")
        end
        fab!(:multi_suggestion) do
          Fabricate(
            :suggested_edit,
            post: multi_post,
            user: suggester,
            raw_suggestion: "ALPHA\nMiddle\nBRAVO\n",
            base_post_version: multi_post.version,
          )
        end

        before do
          DiscourseSuggestedEdits::ChangeExtractor
            .call(original_raw: multi_post.raw, new_raw: multi_suggestion.raw_suggestion)
            .each do |change|
              Fabricate(:suggested_edit_change, suggested_edit: multi_suggestion, **change)
            end
        end

        let(:suggestion_id) { multi_suggestion.id }
        let(:first_change) { multi_suggestion.edit_changes.order(:position).first }
        let(:second_change) { multi_suggestion.edit_changes.order(:position).second }
        let(:accepted_change_ids) { [first_change.id] }
        let(:change_overrides) { { second_change.id.to_s => "SHOULD NOT APPEAR" } }

        it "ignores overrides for change ids that are not accepted" do
          expect { result }.to change { multi_post.reload.raw }.to("ALPHA\nMiddle\nBravo")
        end
      end

      context "when change_overrides is blank" do
        let(:change_overrides) { {} }

        it "applies the original after_text" do
          expect { result }.to change { post.reload.raw }.to("Line one\nLine TWO\nLine three")
        end
      end
    end
  end
end
