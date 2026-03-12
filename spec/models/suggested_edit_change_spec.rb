# frozen_string_literal: true

RSpec.describe SuggestedEditChange do
  fab!(:user)
  fab!(:post)

  describe "validations" do
    it "requires a non-negative start offset" do
      change =
        Fabricate.build(
          :suggested_edit_change,
          suggested_edit: Fabricate(:suggested_edit, post: post, user: user),
          start_offset: -1,
        )

      expect(change).not_to be_valid
      expect(change.errors[:start_offset]).to be_present
    end
  end

  describe "#diff_html" do
    it "returns inline HTML diff" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "hello world",
          after_text: "hello universe",
        )

      html = change.diff_html

      expect(html).to include("diff-del")
      expect(html).to include("diff-ins")
    end
  end
end
