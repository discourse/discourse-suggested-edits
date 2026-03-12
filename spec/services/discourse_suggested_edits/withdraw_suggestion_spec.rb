# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::WithdrawSuggestion do
  describe described_class::Contract, type: :model do
    it { is_expected.to validate_presence_of(:suggestion_id) }
  end

  describe '.call' do
    subject(:result) { described_class.call(params:, **dependencies) }

    fab!(:category)
    fab!(:tag)
    fab!(:suggest_group, :group)
    fab!(:review_group, :group)
    fab!(:acting_user) { Fabricate(:user, groups: [suggest_group]) }
    fab!(:topic) { Fabricate(:topic, category: category, tags: [tag]) }
    fab!(:post) { Fabricate(:post, topic: topic, post_number: 1, raw: "Original content here.\n") }
    fab!(:suggested_edit) do
      Fabricate(:suggested_edit, post: post, user: acting_user, base_post_version: post.version)
    end

    let(:params) { { suggestion_id: suggested_edit.id } }
    let(:dependencies) { { guardian: acting_user.guardian } }

    before do
      SiteSetting.suggested_edits_enabled = true
      SiteSetting.suggested_edits_suggest_group = suggest_group.id.to_s
      SiteSetting.suggested_edits_review_group = review_group.id.to_s
      SiteSetting.suggested_edits_included_categories = category.id.to_s
    end

    context 'when contract is invalid' do
      let(:params) { { suggestion_id: nil } }

      it { is_expected.to fail_a_contract }
    end

    context 'when suggested edit is not found' do
      let(:params) { { suggestion_id: 0 } }

      it { is_expected.to fail_to_find_a_model(:suggested_edit) }
    end

    context 'when user cannot update the suggested edit' do
      fab!(:acting_user, :user)

      it { is_expected.to fail_a_policy(:can_update_suggested_edit) }
    end

    context 'when the suggestion is not pending' do
      before { suggested_edit.update!(status: :dismissed) }

      it { is_expected.to fail_a_policy(:can_update_suggested_edit) }
    end

    context 'when everything is ok' do
      let(:messages) do
        MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") { result }
      end

      it { is_expected.to run_successfully }

      it 'withdraws the suggested edit' do
        expect { result }.to change { suggested_edit.reload.status }.from('pending').to(
          'withdrawn'
        )
      end

      it 'publishes a pending count update' do
        review_message = messages.find { |m| m.data[:type] == 'suggested_edits_changed' }
        expect(review_message.data[:pending_count]).to eq(0)
      end

      it 'publishes a resolved update to the suggester' do
        resolved_message = messages.find { |m| m.data[:type] == 'suggested_edit_resolved' }
        expect(resolved_message.user_ids).to eq([acting_user.id])
      end
    end
  end
end
