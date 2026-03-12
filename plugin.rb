# frozen_string_literal: true

# name: discourse-suggested-edits
# about: Allows users to suggest edits to first posts in configured categories/tags
# version: 0.1.0
# authors: Discourse
# url: https://github.com/discourse/discourse/tree/main/plugins/discourse-suggested-edits

enabled_site_setting :suggested_edits_enabled

register_asset "stylesheets/suggested-edits.scss"

register_svg_icon "pen-to-square"

module ::DiscourseSuggestedEdits
  PLUGIN_NAME = "discourse-suggested-edits"
end

require_relative "lib/discourse_suggested_edits/engine"

after_initialize do
  require_relative "lib/discourse_suggested_edits/change_applier"
  require_relative "lib/discourse_suggested_edits/change_extractor"
  require_relative "lib/discourse_suggested_edits/payload_validator"
  require_relative "lib/discourse_suggested_edits/post_edit_guard"
  require_relative "lib/discourse_suggested_edits/publisher"

  reloadable_patch { Post.has_many :suggested_edits, dependent: :destroy }

  add_to_class(:topic, :preload_suggested_edit_count) do |count|
    @suggested_edit_count = count
    @suggested_edit_count_loaded = true
  end

  add_to_class(:topic, :suggested_edit_count) { @suggested_edit_count }
  add_to_class(:topic, :suggested_edit_count_loaded?) do
    defined?(@suggested_edit_count_loaded) && @suggested_edit_count_loaded
  end

  add_to_class(:topic, :preload_pending_suggested_edit_count) do |count|
    @pending_suggested_edit_count = count
    @pending_suggested_edit_count_loaded = true
  end

  add_to_class(:topic, :pending_suggested_edit_count) { @pending_suggested_edit_count }
  add_to_class(:topic, :pending_suggested_edit_count_loaded?) do
    defined?(@pending_suggested_edit_count_loaded) && @pending_suggested_edit_count_loaded
  end

  add_to_class(:topic, :preload_own_pending_suggested_edit_id) do |suggested_edit_id|
    @own_pending_suggested_edit_id = suggested_edit_id
    @own_pending_suggested_edit_id_loaded = true
  end

  add_to_class(:topic, :own_pending_suggested_edit_id) { @own_pending_suggested_edit_id }
  add_to_class(:topic, :own_pending_suggested_edit_id_loaded?) do
    defined?(@own_pending_suggested_edit_id_loaded) && @own_pending_suggested_edit_id_loaded
  end

  add_to_class(:guardian, :can_suggest_edit?) do |post|
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
    tag_ok = included_tag_names.present? && (topic.tags.pluck(:name) & included_tag_names).present?

    category_ok || tag_ok
  end

  add_to_class(:guardian, :can_update_suggested_edit?) do |suggested_edit|
    return false unless SiteSetting.suggested_edits_enabled
    return false unless user
    return false unless suggested_edit&.post && can_see?(suggested_edit.post)
    return false unless suggested_edit.user_id == user.id

    suggested_edit.pending?
  end

  add_to_class(:guardian, :can_review_suggested_edits_in_topic_list?) do
    return false unless SiteSetting.suggested_edits_enabled
    return false unless user
    return true if user.admin?

    review_group_ids = SiteSetting.suggested_edits_review_group_map
    review_group_ids.present? && user.groups.where(id: review_group_ids).exists?
  end

  add_to_class(:guardian, :can_review_suggested_edits_for_post?) do |post|
    return false unless SiteSetting.suggested_edits_enabled
    return false unless user
    return false unless post && can_see?(post)

    can_review_suggested_edits_in_topic_list? || post&.user_id == user.id
  end

  add_to_class(:guardian, :can_review_suggested_edit?) do |suggested_edit|
    can_review_suggested_edits_for_post?(suggested_edit.post)
  end

  TopicView.on_preload do |topic_view|
    next unless SiteSetting.suggested_edits_enabled

    first_post = topic_view.topic.first_post
    next unless first_post

    if topic_view.guardian.can_review_suggested_edits_for_post?(first_post)
      topic_view.topic.preload_pending_suggested_edit_count(
        SuggestedEdit.pending.where(post_id: first_post.id).count,
      )
    end

    if topic_view.guardian.user
      topic_view.topic.preload_own_pending_suggested_edit_id(
        SuggestedEdit
          .pending
          .where(post_id: first_post.id, user_id: topic_view.guardian.user.id)
          .pick(:id),
      )
    end
  end

  TopicList.on_preload do |topics, topic_list|
    next unless SiteSetting.suggested_edits_enabled
    next if topic_list.current_user.blank? || topics.blank?

    guardian = Guardian.new(topic_list.current_user)
    next unless guardian.can_review_suggested_edits_in_topic_list?

    counts =
      SuggestedEdit
        .pending
        .joins(:post)
        .where(posts: { topic_id: topics.map(&:id), post_number: 1 })
        .group("posts.topic_id")
        .count

    topics.each { |topic| topic.preload_suggested_edit_count(counts[topic.id] || 0) }
  end

  add_to_serializer(
    :post,
    :can_suggest_edit,
    include_condition: -> do
      SiteSetting.suggested_edits_enabled && object.post_number == 1 && scope.user.present?
    end,
  ) { scope.can_suggest_edit?(object) }

  add_to_serializer(
    :topic_view,
    :pending_suggested_edit_count,
    include_condition: -> do
      SiteSetting.suggested_edits_enabled && object.topic.first_post.present? &&
        scope.can_review_suggested_edits_for_post?(object.topic.first_post)
    end,
  ) do
    if object.topic.pending_suggested_edit_count_loaded?
      object.topic.pending_suggested_edit_count
    else
      SuggestedEdit.pending.where(post_id: object.topic.first_post.id).count
    end
  end

  add_to_serializer(
    :topic_view,
    :own_pending_suggested_edit_id,
    include_condition: -> { SiteSetting.suggested_edits_enabled && scope.user.present? },
  ) do
    if object.topic.own_pending_suggested_edit_id_loaded?
      object.topic.own_pending_suggested_edit_id
    else
      SuggestedEdit
        .pending
        .where(post_id: object.topic.first_post&.id, user_id: scope.user.id)
        .pick(:id)
    end
  end

  add_to_serializer(
    :topic_list_item,
    :suggested_edit_count,
    include_condition: -> do
      SiteSetting.suggested_edits_enabled && scope.can_review_suggested_edits_in_topic_list?
    end,
  ) do
    if object.suggested_edit_count_loaded?
      object.suggested_edit_count
    else
      SuggestedEdit.pending.joins(:post).where(posts: { topic_id: object.id, post_number: 1 }).count
    end
  end

  on(:post_edited) do |post|
    next unless post.post_number == 1
    next if DiscourseSuggestedEdits::PostEditGuard.suppressed?(post.id)

    stale_suggestions =
      SuggestedEdit.pending.where(post_id: post.id).where("base_post_version < ?", post.version)
    resolved_user_ids = stale_suggestions.pluck(:user_id)
    next if resolved_user_ids.blank?

    stale_suggestions.update_all(status: SuggestedEdit.statuses[:stale])
    DiscourseSuggestedEdits::Publisher.publish_post_update(
      post: post,
      resolved_user_ids: resolved_user_ids,
    )
  end
end
