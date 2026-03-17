# frozen_string_literal: true

class DiscourseSuggestedEdits::ApplySuggestion
  class ConflictError < StandardError
  end
  class InvalidSelectionError < StandardError
  end
  class InvalidPostRevisionError < StandardError
  end
  class StaleSuggestionError < StandardError
  end

  include Service::Base

  params do
    attribute :suggestion_id, :integer
    attribute :accepted_change_ids, :array
    attribute :change_overrides

    validates :suggestion_id, presence: true
    validate :accepted_change_ids_must_be_array

    def accepted_change_ids_must_be_array
      raw_value = @attributes["accepted_change_ids"]&.value_before_type_cast
      return if raw_value.is_a?(Array)

      errors.add(
        :accepted_change_ids,
        I18n.t("discourse_suggested_edits.errors.invalid_selected_changes"),
      )
    end
  end

  model :suggested_edit
  policy :can_review_suggested_edit
  lock(:suggested_edit) { step :apply_changes }
  step :publish_update

  private

  def fetch_suggested_edit(params:, guardian:)
    suggested_edit =
      SuggestedEdit.includes(:post, :user, :edit_changes).find_by(id: params.suggestion_id)
    return if suggested_edit.blank? || !guardian.can_see?(suggested_edit.post)

    suggested_edit
  end

  def can_review_suggested_edit(guardian:, suggested_edit:)
    guardian.can_review_suggested_edit?(suggested_edit)
  end

  def apply_changes(suggested_edit:, guardian:, params:)
    SuggestedEdit.transaction do
      suggested_edit.lock!
      suggested_edit.post.lock!

      ensure_pending!(suggested_edit)
      accepted_change_ids = normalize_change_ids(params.accepted_change_ids)
      accepted_changes = load_accepted_changes!(suggested_edit, accepted_change_ids)
      apply_overrides!(accepted_changes, params.change_overrides)
      ensure_current_post_version!(suggested_edit)

      new_raw = build_new_raw!(suggested_edit, accepted_changes)
      apply_post_revision!(suggested_edit, new_raw)

      suggested_edit.update!(
        status: :applied,
        applied_by_id: guardian.user.id,
        applied_at: Time.current,
      )

      stale_user_ids = stale_other_suggestions!(suggested_edit)
      context[:resolved_user_ids] = ([suggested_edit.user_id] + stale_user_ids).uniq
    end
  rescue StaleSuggestionError
    suggested_edit.update_columns(status: SuggestedEdit.statuses[:stale], updated_at: Time.zone.now)
    context[:error_status] = :conflict
    fail!(I18n.t("discourse_suggested_edits.errors.stale"))
  rescue InvalidSelectionError => e
    context[:error_status] = :bad_request
    fail!(e.message)
  rescue ConflictError => e
    context[:error_status] = :conflict
    fail!(e.message)
  rescue InvalidPostRevisionError => e
    context[:error_status] = :unprocessable_entity
    fail!(e.message)
  end

  def normalize_change_ids(change_ids)
    normalized_change_ids = Array(change_ids).map(&:to_i).select(&:positive?).uniq

    if normalized_change_ids.blank?
      raise InvalidSelectionError, I18n.t("discourse_suggested_edits.errors.no_selected_changes")
    end

    normalized_change_ids
  end

  def load_accepted_changes!(suggested_edit, accepted_change_ids)
    accepted_changes =
      suggested_edit.edit_changes.where(id: accepted_change_ids).order(:position).to_a

    if accepted_changes.length != accepted_change_ids.length
      raise InvalidSelectionError,
            I18n.t("discourse_suggested_edits.errors.invalid_selected_changes")
    end

    accepted_changes
  end

  def apply_overrides!(accepted_changes, overrides)
    return if overrides.blank?
    overrides_map = overrides.transform_keys { |k| k.to_s.to_i }
    accepted_changes.each do |change|
      change.after_text = overrides_map[change.id] if overrides_map.key?(change.id)
    end
  end

  def ensure_pending!(suggested_edit)
    return if suggested_edit.pending?

    raise ConflictError, I18n.t("discourse_suggested_edits.errors.not_pending")
  end

  def ensure_current_post_version!(suggested_edit)
    raise StaleSuggestionError if suggested_edit.post.version > suggested_edit.base_post_version
  end

  def build_new_raw!(suggested_edit, accepted_changes)
    DiscourseSuggestedEdits::ChangeApplier.call(
      raw: suggested_edit.post.raw,
      changes: accepted_changes,
    )
  rescue DiscourseSuggestedEdits::ChangeApplier::MismatchError
    raise StaleSuggestionError
  end

  def apply_post_revision!(suggested_edit, new_raw)
    revised =
      PostRevisor.new(suggested_edit.post).revise!(
        suggested_edit.user,
        { raw: new_raw },
        edit_reason:
          I18n.t(
            "discourse_suggested_edits.applied_reason",
            username: suggested_edit.user.username,
          ),
        force_new_version: true,
        bypass_rate_limiter: true,
        suggested_edit: true,
      )

    return if revised

    raise InvalidPostRevisionError,
          suggested_edit.post.errors.full_messages.first || I18n.t("invalid_params")
  end

  def stale_other_suggestions!(suggested_edit)
    stale_suggestions =
      SuggestedEdit
        .pending
        .where(post_id: suggested_edit.post_id)
        .where.not(id: suggested_edit.id)
        .where("base_post_version < ?", suggested_edit.post.version)

    stale_user_ids = stale_suggestions.pluck(:user_id)
    if stale_user_ids.present?
      stale_suggestions.update_all(
        status: SuggestedEdit.statuses[:stale],
        updated_at: Time.zone.now,
      )
    end

    stale_user_ids
  end

  def publish_update(suggested_edit:, resolved_user_ids:)
    DiscourseSuggestedEdits::Publisher.publish_post_update(
      post: suggested_edit.post,
      resolved_user_ids: resolved_user_ids,
    )
  end
end
