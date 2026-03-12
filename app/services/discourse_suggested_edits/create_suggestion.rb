# frozen_string_literal: true

class DiscourseSuggestedEdits::CreateSuggestion
  include Service::Base

  params do
    attribute :post_id, :integer
    attribute :raw, :string
    attribute :reason, :string

    validates :post_id, presence: true
    validates :raw, presence: true
  end

  model :post
  policy :can_suggest_edit
  step :enforce_rate_limit
  step :validate_payload

  lock(:post) do
    transaction do
      step :ensure_raw_changed
      step :ensure_no_pending_suggestion
      step :create_suggested_edit
      step :store_changes
    end
  end

  step :publish_update

  private

  def fetch_post(params:, guardian:)
    post = Post.find_by(id: params.post_id)
    return if post.blank? || !guardian.can_see?(post)

    post
  end

  def can_suggest_edit(guardian:, post:)
    guardian.can_suggest_edit?(post)
  end

  def enforce_rate_limit(guardian:)
    RateLimiter.new(
      guardian.user,
      "create_suggested_edit",
      SiteSetting.suggested_edits_max_creates_per_minute,
      1.minute,
    ).performed!
  end

  def validate_payload(params:)
    payload = DiscourseSuggestedEdits::PayloadValidator.new(raw: params.raw, reason: params.reason)
    return if payload.valid?

    fail!(payload.errors.full_messages.first)
  end

  def ensure_raw_changed(post:, params:)
    return if params.raw.strip != post.raw.strip

    fail!(I18n.t("discourse_suggested_edits.errors.no_changes"))
  end

  def ensure_no_pending_suggestion(post:, guardian:)
    return unless SuggestedEdit.pending.exists?(post_id: post.id, user_id: guardian.user.id)

    fail!(I18n.t("discourse_suggested_edits.errors.already_pending"))
  end

  def create_suggested_edit(post:, guardian:, params:)
    context[:suggested_edit] = SuggestedEdit.create!(
      post: post,
      user: guardian.user,
      raw_suggestion: params.raw,
      base_post_version: post.version,
      status: :pending,
      reason: params.reason,
    )
  rescue ActiveRecord::RecordNotUnique
    fail!(I18n.t("discourse_suggested_edits.errors.already_pending"))
  end

  def store_changes(post:, params:, suggested_edit:)
    DiscourseSuggestedEdits::ChangeExtractor
      .call(original_raw: post.raw, new_raw: params.raw)
      .each { |change| suggested_edit.edit_changes.create!(change) }
  end

  def publish_update(post:)
    DiscourseSuggestedEdits::Publisher.publish_post_update(post: post)
  end
end
