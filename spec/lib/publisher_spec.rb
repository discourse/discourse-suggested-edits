# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::Publisher do
  fab!(:category)
  fab!(:tag)
  fab!(:review_group, :group)
  fab!(:post_author) { Fabricate(:user) }
  fab!(:topic) { Fabricate(:topic, category: category, tags: [tag], user: post_author) }
  fab!(:post) { Fabricate(:post, topic: topic, post_number: 1, user: post_author) }

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_review_group = review_group.id.to_s
  end

  describe '.publish_post_update' do
    let(:channel) { "/suggested-edits/topic/#{topic.id}" }

    def messages
      @messages ||= MessageBus.track_publish(channel) do
        described_class.publish_post_update(post: post, resolved_user_ids: resolved_user_ids)
      end
    end

    def review_message
      messages.find { |m| m.data[:type] == 'suggested_edits_changed' }
    end

    def resolved_message
      messages.find { |m| m.data[:type] == 'suggested_edit_resolved' }
    end

    context 'with a public topic' do
      let(:resolved_user_ids) { [post_author.id] }

      it 'targets the review update to the post author' do
        expect(review_message.user_ids).to eq([post_author.id])
      end

      it 'targets the review update to review and admin groups' do
        expect(review_message.group_ids).to contain_exactly(
          review_group.id, Group::AUTO_GROUPS[:admins]
        )
      end

      it 'targets the resolved update to the specified user ids' do
        expect(resolved_message.user_ids).to eq([post_author.id])
      end

      it 'does not target the resolved update to any groups' do
        expect(resolved_message.group_ids).to be_nil
      end
    end

    context 'with a private message' do
      fab!(:pm_reviewer) { Fabricate(:user, groups: [review_group]) }
      fab!(:outsider_reviewer) { Fabricate(:user, groups: [review_group]) }
      fab!(:topic) { Fabricate(:private_message_topic, user: post_author) }
      fab!(:post) { Fabricate(:post, topic: topic, post_number: 1, user: post_author) }

      let(:resolved_user_ids) { nil }

      before { topic.topic_allowed_users.create!(user: pm_reviewer) }

      it 'includes allowed PM participants in the review audience' do
        expect(review_message.user_ids).to include(post_author.id, pm_reviewer.id)
      end

      it 'excludes review group members not in the PM' do
        expect(review_message.user_ids).not_to include(outsider_reviewer.id)
      end

      it 'does not use group_ids for the review update' do
        expect(review_message.group_ids).to be_nil
      end

      it 'does not publish a resolved update when resolved_user_ids is nil' do
        expect(resolved_message).to be_nil
      end
    end

    context 'with a secure category topic' do
      fab!(:secure_group, :group)
      fab!(:allowed_reviewer) { Fabricate(:user, groups: [review_group, secure_group]) }
      fab!(:excluded_reviewer) { Fabricate(:user, groups: [review_group]) }
      fab!(:category) { Fabricate(:private_category, group: secure_group) }
      fab!(:topic) { Fabricate(:topic, category: category, user: post_author) }
      fab!(:post) { Fabricate(:post, topic: topic, post_number: 1, user: post_author) }

      let(:resolved_user_ids) { nil }

      it 'includes review group members with category access' do
        expect(review_message.user_ids).to include(post_author.id, allowed_reviewer.id)
      end

      it 'excludes review group members without category access' do
        expect(review_message.user_ids).not_to include(excluded_reviewer.id)
      end

      it 'does not use group_ids for the review update' do
        expect(review_message.group_ids).to be_nil
      end
    end

    context 'with no topic' do
      let(:resolved_user_ids) { [post_author.id] }

      it 'does not publish any messages' do
        topic_id = topic.id
        post.topic.destroy!
        post.reload

        published =
          MessageBus.track_publish("/suggested-edits/topic/#{topic_id}") do
            described_class.publish_post_update(post: post, resolved_user_ids: resolved_user_ids)
          end

        expect(published).to be_empty
      end
    end
  end
end
