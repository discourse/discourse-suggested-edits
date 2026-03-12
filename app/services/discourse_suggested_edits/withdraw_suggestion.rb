# frozen_string_literal: true

class DiscourseSuggestedEdits::WithdrawSuggestion
  include Service::Base

  params do
    attribute :suggestion_id, :integer

    validates :suggestion_id, presence: true
  end

  model :suggested_edit
  policy :can_update_suggested_edit

  lock(:suggested_edit) do
    transaction do
      step :lock_records
      step :ensure_pending
      step :store_publish_data
      step :withdraw
    end
  end

  step :publish_update

  private

  def fetch_suggested_edit(params:, guardian:)
    suggested_edit = SuggestedEdit.includes(:post).find_by(id: params.suggestion_id)
    return if suggested_edit.blank? || !guardian.can_see?(suggested_edit.post)

    suggested_edit
  end

  def can_update_suggested_edit(guardian:, suggested_edit:)
    guardian.can_update_suggested_edit?(suggested_edit)
  end

  def lock_records(suggested_edit:)
    suggested_edit.lock!
    suggested_edit.post.lock!
  end

  def ensure_pending(suggested_edit:)
    return if suggested_edit.pending?

    fail!(I18n.t("discourse_suggested_edits.errors.not_pending"))
  end

  def store_publish_data(suggested_edit:)
    context[:post] = suggested_edit.post
    context[:resolved_user_ids] = [suggested_edit.user_id]
  end

  def withdraw(suggested_edit:)
    suggested_edit.update!(status: :withdrawn)
  end

  def publish_update(post:, resolved_user_ids:)
    DiscourseSuggestedEdits::Publisher.publish_post_update(
      post: post,
      resolved_user_ids: resolved_user_ids,
    )
  end
end
