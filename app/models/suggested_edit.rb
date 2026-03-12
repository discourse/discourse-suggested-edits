# frozen_string_literal: true

class SuggestedEdit < ActiveRecord::Base
  belongs_to :post
  belongs_to :user
  belongs_to :applied_by, class_name: "User", optional: true
  has_many :edit_changes,
           -> { order(:position) },
           class_name: "SuggestedEditChange",
           dependent: :destroy

  enum :status, { pending: 0, applied: 1, dismissed: 2, stale: 3, withdrawn: 4 }

  scope :pending, -> { where(status: statuses[:pending]) }

  validates :raw_suggestion, presence: true
  validates :base_post_version, presence: true
  validate :single_pending_suggestion_per_user, if: :pending?

  private

  def single_pending_suggestion_per_user
    relation = self.class.pending.where(post_id: post_id, user_id: user_id)
    relation = relation.where.not(id: id) if persisted?

    return unless relation.exists?

    errors.add(:base, I18n.t("discourse_suggested_edits.errors.already_pending"))
  end
end

# == Schema Information
#
# Table name: suggested_edits
#
#  id                :bigint           not null, primary key
#  applied_at        :datetime
#  base_post_version :integer          not null
#  raw_suggestion    :text             not null
#  reason            :text
#  status            :integer          default("pending"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  applied_by_id     :integer
#  post_id           :integer          not null
#  user_id           :integer          not null
#
# Indexes
#
#  index_suggested_edits_on_post_id_and_status  (post_id,status)
#  index_suggested_edits_on_status              (status)
#  index_suggested_edits_on_user_id             (user_id)
#
