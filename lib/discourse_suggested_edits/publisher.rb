# frozen_string_literal: true

module DiscourseSuggestedEdits
  module Publisher
    module_function

    def publish_post_update(post:, resolved_user_ids: nil)
      topic = post.topic
      return unless topic

      MessageBus.publish(
        "/suggested-edits/topic/#{topic.id}",
        {
          type: "suggested_edits_changed",
          pending_count: SuggestedEdit.pending.where(post_id: post.id).count,
        },
        **review_audience_publish_options(post: post, topic: topic),
      )

      publish_resolved_users(topic: topic, resolved_user_ids: resolved_user_ids)
    end

    def publish_resolved_users(topic:, resolved_user_ids:)
      user_ids = resolved_user_ids.to_a.compact.uniq
      return if user_ids.blank?

      MessageBus.publish(
        "/suggested-edits/topic/#{topic.id}",
        { type: "suggested_edit_resolved" },
        user_ids: user_ids,
      )
    end

    def review_audience_publish_options(post:, topic:)
      if topic.private_message? || topic.secure_group_ids.present?
        { user_ids: review_audience_user_ids(post: post, topic: topic) }
      else
        { user_ids: [post.user_id], group_ids: review_audience_group_ids }
      end
    end

    def review_audience_group_ids
      (SiteSetting.suggested_edits_review_group_map + [Group::AUTO_GROUPS[:admins]]).uniq
    end

    def review_audience_user_ids(post:, topic:)
      user_ids = User.human_users.where(admin: true).pluck(:id)
      user_ids << post.user_id

      review_group_ids = SiteSetting.suggested_edits_review_group_map
      if review_group_ids.present?
        review_group_members = GroupUser.where(group_id: review_group_ids)

        if topic.private_message?
          allowed_user_ids = topic.secure_audience_publish_messages[:user_ids]
          review_group_members = review_group_members.where(user_id: allowed_user_ids)
        elsif topic.secure_group_ids.present?
          review_group_members =
            review_group_members.where(
              user_id: GroupUser.where(group_id: topic.secure_group_ids).select(:user_id),
            )
        end

        user_ids.concat(review_group_members.pluck(:user_id))
      end

      user_ids.compact.uniq
    end
  end
end
