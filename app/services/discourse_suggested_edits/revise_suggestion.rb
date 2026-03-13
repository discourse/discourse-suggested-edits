# frozen_string_literal: true

class DiscourseSuggestedEdits::ReviseSuggestion
  include Service::Base

  params do
    attribute :suggestion_id, :integer
    attribute :raw, :string
    attribute :reason, :string

    validates :suggestion_id, presence: true
    validates :raw, presence: true
  end

  model :suggested_edit
  policy :can_update_suggested_edit
  step :validate_payload

  lock(:suggested_edit) do
    transaction do
      step :lock_records
      step :ensure_pending
      step :ensure_raw_changed
      step :replace_suggestion
      step :store_changes
    end
  end

  step :publish_update

  private

  def fetch_suggested_edit(params:, guardian:)
    suggested_edit = SuggestedEdit.includes(:post, :edit_changes).find_by(id: params.suggestion_id)
    return if suggested_edit.blank? || !guardian.can_see?(suggested_edit.post)

    suggested_edit
  end

  def can_update_suggested_edit(guardian:, suggested_edit:)
    guardian.can_update_suggested_edit?(suggested_edit)
  end

  def validate_payload(params:)
    payload = DiscourseSuggestedEdits::PayloadValidator.new(raw: params.raw, reason: params.reason)
    return if payload.valid?

    fail!(payload.errors.full_messages.first)
  end

  def lock_records(suggested_edit:)
    suggested_edit.lock!
    suggested_edit.post.lock!
  end

  def ensure_pending(suggested_edit:)
    return if suggested_edit.pending?

    fail!(I18n.t("discourse_suggested_edits.errors.not_pending"))
  end

  def ensure_raw_changed(suggested_edit:, params:)
    return if params.raw.strip != suggested_edit.post.raw.strip

    fail!(I18n.t("discourse_suggested_edits.errors.no_changes"))
  end

  def replace_suggestion(suggested_edit:, params:)
    suggested_edit.edit_changes.delete_all
    suggested_edit.update!(
      raw_suggestion: params.raw,
      reason: params.reason.nil? ? suggested_edit.reason : params.reason,
      base_post_version: suggested_edit.post.version,
    )
  end

  def store_changes(suggested_edit:, params:)
    DiscourseSuggestedEdits::ChangeExtractor
      .call(original_raw: suggested_edit.post.raw, new_raw: params.raw)
      .each { |change| suggested_edit.edit_changes.create!(change) }
  end

  def publish_update(suggested_edit:)
    DiscourseSuggestedEdits::Publisher.publish_post_update(post: suggested_edit.post)
  end
end
