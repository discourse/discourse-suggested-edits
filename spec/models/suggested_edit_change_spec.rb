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

    it "merges consecutive replacements into a single block" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "A wiki post is great",
          after_text: "A wikia posta is great",
        )

      html = change.diff_html

      expect(html).to include("<del class=\"diff-del\">wiki post</del>")
      expect(html).to include("<ins class=\"diff-ins\">wikia posta</ins>")
      expect(html).not_to include("</del> <del")
    end

    it "merges consecutive deletions into a single block" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "remove these three words please",
          after_text: "remove please",
        )

      html = change.diff_html

      expect(html).to include("<del class=\"diff-del\">these three words </del>")
      expect(html).not_to include("</del> <del")
    end

    it "merges consecutive insertions into a single block" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "add please",
          after_text: "add these three words please",
        )

      html = change.diff_html

      expect(html).to include("<ins class=\"diff-ins\">these three words </ins>")
      expect(html).not_to include("</ins> <ins")
    end

    it "keeps non-consecutive changes separate" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "hello world foo bar",
          after_text: "hello earth foo baz",
        )

      html = change.diff_html

      expect(html).to include("<del class=\"diff-del\">world</del>")
      expect(html).to include("<ins class=\"diff-ins\">earth</ins>")
      expect(html).to include("<del class=\"diff-del\">bar</del>")
      expect(html).to include("<ins class=\"diff-ins\">baz</ins>")
    end

    it "does not merge changes across newlines" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "hello\nworld",
          after_text: "hi\nearth",
        )

      html = change.diff_html

      expect(html).to include("<del class=\"diff-del\">hello</del>")
      expect(html).to include("<del class=\"diff-del\">world</del>")
      expect(html).to include("<ins class=\"diff-ins\">hi</ins>")
      expect(html).to include("<ins class=\"diff-ins\">earth</ins>")
    end

    it "does not mark unchanged words as edited when deleting trailing newlines" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text:
            "A: Yes, any post in a topic can be converted to a wiki, not just the first post.\n\nTo summarise, this is my edit!",
          after_text:
            "A: Yes, any post in a topic can be converted to a WIKI, not just the first post.",
        )

      html = change.diff_html

      expect(html).to include("not just the first post.<del class=\"diff-del\">\n\nTo summarise")
      expect(html).not_to include("<del class=\"diff-del\">post.")
      expect(html).not_to include("<ins class=\"diff-ins\">post.")
    end
  end

  describe "#side_by_side_diff" do
    it "merges consecutive replacements in both before and after" do
      suggested_edit = Fabricate(:suggested_edit, post: post, user: user)
      change =
        Fabricate(
          :suggested_edit_change,
          suggested_edit: suggested_edit,
          before_text: "A wiki post is great",
          after_text: "A wikia posta is great",
        )

      result = change.side_by_side_diff

      expect(result[:before]).to include("<del class=\"diff-del\">wiki post</del>")
      expect(result[:before]).not_to include("</del> <del")
      expect(result[:after]).to include("<ins class=\"diff-ins\">wikia posta</ins>")
      expect(result[:after]).not_to include("</ins> <ins")
    end
  end

  context "when the word diff is too complex" do
    fab!(:change) do
      Fabricate(
        :suggested_edit_change,
        suggested_edit: Fabricate(:suggested_edit, post: post, user: user),
        before_text: "<b>old</b> words",
        after_text: "new words",
      )
    end

    before do
      allow_any_instance_of(ONPDiff).to receive(:short_diff).and_raise(
        ONPDiff::DiffLimitExceeded.new(
          comparisons_used: 1,
          comparison_budget: 1,
          left_size: 1,
          right_size: 1,
        ),
      )
    end

    it "shows the whole hunk as escaped source" do
      expect(change.diff_html).to eq(
        "<div class=\"inline-diff\"><del class=\"diff-del\">&lt;b&gt;old&lt;/b&gt; words</del><ins class=\"diff-ins\">new words</ins></div>",
      )
      expect(change.side_by_side_diff).to eq(
        before:
          "<div class=\"side-by-side-diff__before\"><del class=\"diff-del\">&lt;b&gt;old&lt;/b&gt; words</del></div>",
        after:
          "<div class=\"side-by-side-diff__after\"><ins class=\"diff-ins\">new words</ins></div>",
      )
    end
  end
end
