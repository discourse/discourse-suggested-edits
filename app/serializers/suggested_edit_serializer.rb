# frozen_string_literal: true

class SuggestedEditSerializer < ApplicationSerializer
  attributes :id,
             :post_id,
             :raw_suggestion,
             :base_post_version,
             :status,
             :reason,
             :created_at,
             :updated_at,
             :applied_at

  has_one :user, serializer: BasicUserSerializer, embed: :objects
  has_one :applied_by, serializer: BasicUserSerializer, embed: :objects
  has_many :edit_changes, serializer: SuggestedEditChangeSerializer, embed: :objects, key: :changes
end
