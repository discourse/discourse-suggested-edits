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
  require_relative "lib/discourse_suggested_edits/register_filters"
  require_relative "lib/discourse_suggested_edits/change_applier"
  require_relative "lib/discourse_suggested_edits/change_extractor"
  require_relative "lib/discourse_suggested_edits/payload_validator"
  require_relative "lib/discourse_suggested_edits/guardian_extensions"
  require_relative "lib/discourse_suggested_edits/publisher"

  DiscourseSuggestedEdits::RegisterFilters.register(self)

  add_api_key_scope(
    :discourse_suggested_edits,
    {
      suggest_edits: {
        actions: %w[
          discourse_suggested_edits/suggestions#index
          discourse_suggested_edits/suggestions#show
          discourse_suggested_edits/suggestions#create
          discourse_suggested_edits/suggestions#update
          discourse_suggested_edits/suggestions#destroy
        ],
      },
    },
  )

  reloadable_patch do
    Post.has_many :suggested_edits, dependent: :destroy
    Guardian.prepend(DiscourseSuggestedEdits::GuardianExtensions)
  end

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

  add_to_class(:topic, :preload_can_review_suggested_edits_for_first_post) do |value|
    @can_review_suggested_edits_for_first_post = value
    @can_review_suggested_edits_for_first_post_loaded = true
  end

  add_to_class(:topic, :can_review_suggested_edits_for_first_post) do
    @can_review_suggested_edits_for_first_post
  end

  add_to_class(:topic, :can_review_suggested_edits_for_first_post_loaded?) do
    defined?(@can_review_suggested_edits_for_first_post_loaded) &&
      @can_review_suggested_edits_for_first_post_loaded
  end

  TopicView.on_preload do |topic_view|
    next unless SiteSetting.suggested_edits_enabled

    first_post = topic_view.topic.first_post
    next unless first_post

    can_review_suggested_edits_for_first_post =
      topic_view.guardian.can_review_suggested_edits_for_post?(first_post)
    topic_view.topic.preload_can_review_suggested_edits_for_first_post(
      can_review_suggested_edits_for_first_post,
    )

    if can_review_suggested_edits_for_first_post
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
        if object.topic.can_review_suggested_edits_for_first_post_loaded?
          object.topic.can_review_suggested_edits_for_first_post
        else
          scope.can_review_suggested_edits_for_post?(object.topic.first_post)
        end
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

  on(:post_edited) do |post, _, revisor|
    next unless post.post_number == 1
    next if revisor&.opts&.dig(:suggested_edit)

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
