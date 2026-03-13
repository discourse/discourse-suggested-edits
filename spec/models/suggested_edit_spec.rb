# frozen_string_literal: true

RSpec.describe SuggestedEdit do
  fab!(:user)
  fab!(:post)

  describe "associations" do
    it "belongs to post and user" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)

      expect(suggested_edit.post).to eq(post)
      expect(suggested_edit.user).to eq(user)
    end

    it "orders changes by position" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      later_change = Fabricate(:suggested_edit_change, suggested_edit: suggested_edit, position: 2)
      earlier_change =
        Fabricate(:suggested_edit_change, suggested_edit: suggested_edit, position: 1)

      expect(suggested_edit.edit_changes).to eq([earlier_change, later_change])
    end

    it "destroys changes when destroyed" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      Fabricate(:suggested_edit_change, suggested_edit: suggested_edit)

      expect { suggested_edit.destroy! }.to change { SuggestedEditChange.count }.by(-1)
    end
  end

  describe "validations" do
    it "rejects a second pending suggestion for the same post and user" do
      Fabricate(:suggested_edit, post: post, user: user, status: :pending)
      duplicate = Fabricate.build(:suggested_edit, post: post, user: user, status: :pending)

      expect(duplicate).not_to be_valid
      expect(duplicate.errors.full_messages).to include(
        I18n.t("discourse_suggested_edits.errors.already_pending"),
      )
    end
  end

  describe "enum status" do
    it "supports all statuses" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)

      suggested_edit.update!(status: :applied)
      expect(suggested_edit).to be_applied

      suggested_edit.update!(status: :dismissed)
      expect(suggested_edit).to be_dismissed

      suggested_edit.update!(status: :stale)
      expect(suggested_edit).to be_stale
    end
  end

  describe "scopes" do
    it ".pending returns only pending suggestions" do
      pending_suggestion = Fabricate(:suggested_edit, post: post, user: user, status: :pending)
      applied_suggestion =
        Fabricate(:suggested_edit, post: post, user: Fabricate(:user), status: :applied)

      expect(
        SuggestedEdit.pending.where(id: [pending_suggestion.id, applied_suggestion.id]),
      ).to contain_exactly(pending_suggestion)
    end
  end
end
