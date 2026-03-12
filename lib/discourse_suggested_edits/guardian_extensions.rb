# frozen_string_literal: true

module DiscourseSuggestedEdits
  module GuardianExtensions
    def can_suggest_edit?(post)
      return false unless SiteSetting.suggested_edits_enabled
      return false unless user
      return false unless post && can_see?(post)
      return false unless post.post_number == 1

      suggest_group_ids = SiteSetting.suggested_edits_suggest_group_map
      return false if suggest_group_ids.blank?
      return false unless user.groups.where(id: suggest_group_ids).exists?

      topic = post.topic
      return false unless topic

      included_category_ids = SiteSetting.suggested_edits_included_categories_map
      included_tag_names =
        SiteSetting.suggested_edits_included_tags.to_s.split("|").map(&:strip).reject(&:blank?)

      category_ok =
        included_category_ids.present? && included_category_ids.include?(topic.category_id)
      tag_ok =
        included_tag_names.present? && (topic.tags.pluck(:name) & included_tag_names).present?

      category_ok || tag_ok
    end

    def can_update_suggested_edit?(suggested_edit)
      return false unless SiteSetting.suggested_edits_enabled
      return false unless user
      return false unless suggested_edit&.post && can_see?(suggested_edit.post)
      return false unless suggested_edit.user_id == user.id

      suggested_edit.pending?
    end

    def can_review_suggested_edits_in_topic_list?
      return false unless SiteSetting.suggested_edits_enabled
      return false unless user
      return true if user.admin?

      review_group_ids = SiteSetting.suggested_edits_review_group_map
      review_group_ids.present? && user.groups.where(id: review_group_ids).exists?
    end

    def can_review_suggested_edits_for_post?(post)
      return false unless SiteSetting.suggested_edits_enabled
      return false unless user
      return false unless post && can_see?(post)

      can_review_suggested_edits_in_topic_list? || post&.user_id == user.id
    end

    def can_review_suggested_edit?(suggested_edit)
      can_review_suggested_edits_for_post?(suggested_edit.post)
    end
  end
end
