# frozen_string_literal: true

module DiscourseSuggestedEdits
  class WithdrawSuggestion
    include Service::Base

    params do
      attribute :suggestion_id, :integer

      validates :suggestion_id, presence: true
    end

    model :suggested_edit
    policy :can_see_post
    policy :can_update_suggested_edit
    policy :suggestion_is_pending
    step :withdraw
    step :publish_update

    private

    def fetch_suggested_edit(params:)
      SuggestedEdit.includes(:post).find_by(id: params.suggestion_id)
    end

    def can_see_post(guardian:, suggested_edit:)
      guardian.can_see?(suggested_edit.post)
    end

    def can_update_suggested_edit(guardian:, suggested_edit:)
      guardian.can_update_suggested_edit?(suggested_edit)
    end

    def suggestion_is_pending(suggested_edit:)
      suggested_edit.pending?
    end

    def withdraw(suggested_edit:)
      suggested_edit.update!(status: :withdrawn)
    end

    def publish_update(suggested_edit:)
      DiscourseSuggestedEdits::Publisher.publish_post_update(
        post: suggested_edit.post,
        resolved_user_ids: [suggested_edit.user_id],
      )
    end
  end
end
