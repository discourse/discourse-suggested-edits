# frozen_string_literal: true

module DiscourseSuggestedEdits
  class SuggestionsController < ::ApplicationController
    requires_plugin DiscourseSuggestedEdits::PLUGIN_NAME
    requires_login
    before_action :rate_limit_create!, only: :create
    before_action :rate_limit_revise!, only: :update

    def index
      post = Post.find(params.require(:post_id))
      raise Discourse::NotFound unless guardian.can_see?(post)

      suggestions =
        SuggestedEdit.pending.where(post_id: post.id).includes(:user, :applied_by, :edit_changes)
      suggestions =
        suggestions.where(
          user_id: current_user.id,
        ) unless guardian.can_review_suggested_edits_for_post?(post)

      render json: suggestions, each_serializer: SuggestedEditSerializer, root: "suggested_edits"
    end

    def show
      suggestion =
        SuggestedEdit.includes(:user, :applied_by, :edit_changes, :post).find(params[:id])
      raise Discourse::NotFound unless guardian.can_see?(suggestion.post)
      raise Discourse::InvalidAccess unless can_view?(suggestion)

      render_suggested_edit(suggestion)
    end

    def create
      DiscourseSuggestedEdits::CreateSuggestion.call(
        service_params.deep_merge(params: create_params),
      ) do
        on_success { |suggested_edit:| render_suggested_edit(suggested_edit, status: :created) }
        on_model_not_found(:post) { raise Discourse::NotFound }
        on_failed_policy(:can_suggest_edit) { raise Discourse::InvalidAccess }
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages.first, status: :bad_request)
        end
        on_failed_step(:validate_payload) do |step|
          render_json_error(step.error, status: :bad_request)
        end
        on_failed_step(:ensure_raw_changed) do |step|
          render_json_error(step.error, status: :bad_request)
        end
        on_failed_step(:ensure_no_pending_suggestion) do |step|
          render_json_error(step.error, status: :bad_request)
        end
      end
    end

    def update
      DiscourseSuggestedEdits::ReviseSuggestion.call(
        service_params.deep_merge(params: update_params),
      ) do
        on_success { |suggested_edit:| render_suggested_edit(suggested_edit) }
        on_model_not_found(:suggested_edit) { raise Discourse::NotFound }
        on_failed_policy(:can_update_suggested_edit) { raise Discourse::InvalidAccess }
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages.first, status: :bad_request)
        end
        on_failed_step(:validate_payload) do |step|
          render_json_error(step.error, status: :bad_request)
        end
        on_failed_step(:ensure_pending) { |step| render_json_error(step.error, status: :conflict) }
        on_failed_step(:ensure_raw_changed) do |step|
          render_json_error(step.error, status: :bad_request)
        end
      end
    end

    def destroy
      DiscourseSuggestedEdits::WithdrawSuggestion.call(
        service_params.deep_merge(params: { suggestion_id: params[:id] }),
      ) do
        on_success { head :no_content }
        on_model_not_found(:suggested_edit) { raise Discourse::NotFound }
        on_failed_policy(:can_see_post) { raise Discourse::NotFound }
        on_failed_policy(:can_update_suggested_edit) { raise Discourse::InvalidAccess }
        on_failed_policy(:suggestion_is_pending) do
          render_json_error(
            I18n.t("discourse_suggested_edits.errors.not_pending"),
            status: :conflict,
          )
        end
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages.first, status: :bad_request)
        end
      end
    end

    def apply
      DiscourseSuggestedEdits::ApplySuggestion.call(
        service_params.deep_merge(params: apply_params),
      ) do
        on_success { head :no_content }
        on_model_not_found(:suggested_edit) { raise Discourse::NotFound }
        on_failed_policy(:can_review_suggested_edit) { raise Discourse::InvalidAccess }
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages.first, status: :bad_request)
        end
        on_failed_step(:apply_changes) do |step, error_status:|
          render_json_error(step.error, status: error_status || :unprocessable_entity)
        end
      end
    end

    def dismiss
      DiscourseSuggestedEdits::DismissSuggestion.call(
        service_params.deep_merge(params: { suggestion_id: params[:id] }),
      ) do
        on_success { head :no_content }
        on_model_not_found(:suggested_edit) { raise Discourse::NotFound }
        on_failed_policy(:can_see_post) { raise Discourse::NotFound }
        on_failed_policy(:can_review_suggested_edit) { raise Discourse::InvalidAccess }
        on_failed_policy(:suggestion_is_pending) do
          render_json_error(
            I18n.t("discourse_suggested_edits.errors.not_pending"),
            status: :conflict,
          )
        end
        on_failed_contract do |contract|
          render_json_error(contract.errors.full_messages.first, status: :bad_request)
        end
      end
    end

    private

    def can_view?(suggestion)
      guardian.can_review_suggested_edit?(suggestion) ||
        guardian.can_update_suggested_edit?(suggestion)
    end

    def create_params
      params.permit(:post_id, :raw, :reason).to_h
    end

    def update_params
      params.permit(:raw, :reason).to_h.merge(suggestion_id: params[:id])
    end

    def apply_params
      params
        .permit(accepted_change_ids: [], change_overrides: {})
        .to_h
        .merge(suggestion_id: params[:id])
    end

    def rate_limit_create!
      RateLimiter.new(
        current_user,
        "create_suggested_edit",
        SiteSetting.suggested_edits_max_creates_per_minute,
        1.minute,
      ).performed!
    end

    def rate_limit_revise!
      RateLimiter.new(
        current_user,
        "revise_suggested_edit",
        SiteSetting.suggested_edits_max_revisions_per_minute,
        1.minute,
      ).performed!
    end

    def render_suggested_edit(suggested_edit, status: :ok)
      render json: suggested_edit,
             serializer: SuggestedEditSerializer,
             root: "suggested_edit",
             status: status
    end
  end
end
