# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::GuardianExtensions do
  fab!(:category)
  fab!(:tag)
  fab!(:suggest_group, :group)
  fab!(:review_group, :group)
  fab!(:suggester) { Fabricate(:user, groups: [suggest_group]) }
  fab!(:reviewer) { Fabricate(:user, groups: [review_group]) }
  fab!(:topic) { Fabricate(:topic, category: category, tags: [tag]) }
  fab!(:first_post) { Fabricate(:post, topic: topic, post_number: 1) }

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_suggest_group = suggest_group.id.to_s
    SiteSetting.suggested_edits_review_group = review_group.id.to_s
    SiteSetting.suggested_edits_included_categories = category.id.to_s
  end

  describe "#can_suggest_edit?" do
    it "returns true for a user in the suggest group on an included category" do
      expect(suggester.guardian.can_suggest_edit?(first_post)).to eq(true)
    end

    it "returns false when the plugin is disabled" do
      SiteSetting.suggested_edits_enabled = false
      expect(suggester.guardian.can_suggest_edit?(first_post)).to eq(false)
    end

    it "returns false for anonymous users" do
      expect(Guardian.new.can_suggest_edit?(first_post)).to eq(false)
    end

    it "returns false when the user is not in the suggest group" do
      expect(Fabricate(:user).guardian.can_suggest_edit?(first_post)).to eq(false)
    end

    it "returns false when no suggest group is configured" do
      SiteSetting.suggested_edits_suggest_group = ""
      expect(suggester.guardian.can_suggest_edit?(first_post)).to eq(false)
    end

    it "returns false for non-first posts" do
      reply = Fabricate(:post, topic: topic, post_number: 2)
      expect(suggester.guardian.can_suggest_edit?(reply)).to eq(false)
    end

    it "returns false when the post is nil" do
      expect(suggester.guardian.can_suggest_edit?(nil)).to eq(false)
    end

    it "returns false when the user cannot see the post" do
      private_group = Fabricate(:group)
      private_category = Fabricate(:private_category, group: private_group)
      hidden_topic = Fabricate(:topic, category: private_category)
      hidden_post = Fabricate(:post, topic: hidden_topic, post_number: 1)

      SiteSetting.suggested_edits_included_categories = "#{category.id}|#{private_category.id}"
      expect(suggester.guardian.can_suggest_edit?(hidden_post)).to eq(false)
    end

    it "returns false when the topic category is not included" do
      other_category = Fabricate(:category)
      other_topic = Fabricate(:topic, category: other_category)
      other_post = Fabricate(:post, topic: other_topic, post_number: 1)
      expect(suggester.guardian.can_suggest_edit?(other_post)).to eq(false)
    end

    it "returns true when the topic matches an included tag" do
      SiteSetting.suggested_edits_included_categories = ""
      SiteSetting.suggested_edits_included_tags = tag.name
      expect(suggester.guardian.can_suggest_edit?(first_post)).to eq(true)
    end

    it "returns false when neither category nor tags match" do
      SiteSetting.suggested_edits_included_categories = ""
      SiteSetting.suggested_edits_included_tags = ""
      expect(suggester.guardian.can_suggest_edit?(first_post)).to eq(false)
    end

    it "memoizes suggest group membership checks on a guardian instance" do
      guardian = suggester.guardian

      queries = track_sql_queries { 3.times { guardian.can_suggest_edit?(first_post) } }

      membership_queries =
        queries.filter do |query|
          query.include?(%("group_users"."user_id" = #{suggester.id})) &&
            query.include?(%("groups"."id" = #{suggest_group.id}))
        end

      expect(membership_queries.size).to eq(1)
    end
  end

  describe "#can_update_suggested_edit?" do
    fab!(:suggestion) do
      Fabricate(
        :suggested_edit,
        post: first_post,
        user: suggester,
        base_post_version: first_post.version,
      )
    end

    it "returns true for the suggestion author when pending" do
      expect(suggester.guardian.can_update_suggested_edit?(suggestion)).to eq(true)
    end

    it "returns false when the plugin is disabled" do
      SiteSetting.suggested_edits_enabled = false
      expect(suggester.guardian.can_update_suggested_edit?(suggestion)).to eq(false)
    end

    it "returns false for anonymous users" do
      expect(Guardian.new.can_update_suggested_edit?(suggestion)).to eq(false)
    end

    it "returns false for a different user" do
      expect(reviewer.guardian.can_update_suggested_edit?(suggestion)).to eq(false)
    end

    it "returns false when the suggestion is no longer pending" do
      suggestion.update!(status: :applied)
      expect(suggester.guardian.can_update_suggested_edit?(suggestion)).to eq(false)
    end

    it "returns false when the user can no longer see the post" do
      private_group = Fabricate(:group)
      private_category = Fabricate(:private_category, group: private_group)
      first_post.topic.update!(category: private_category)
      expect(suggester.guardian.can_update_suggested_edit?(suggestion)).to eq(false)
    end
  end

  describe "#can_review_suggested_edits_in_topic_list?" do
    it "returns true for users in the review group" do
      expect(reviewer.guardian.can_review_suggested_edits_in_topic_list?).to eq(true)
    end

    it "returns true for admins" do
      admin = Fabricate(:admin)
      expect(admin.guardian.can_review_suggested_edits_in_topic_list?).to eq(true)
    end

    it "returns false when the plugin is disabled" do
      SiteSetting.suggested_edits_enabled = false
      expect(reviewer.guardian.can_review_suggested_edits_in_topic_list?).to eq(false)
    end

    it "returns false for anonymous users" do
      expect(Guardian.new.can_review_suggested_edits_in_topic_list?).to eq(false)
    end

    it "returns false for users not in the review group" do
      expect(suggester.guardian.can_review_suggested_edits_in_topic_list?).to eq(false)
    end

    it "returns false when no review group is configured" do
      SiteSetting.suggested_edits_review_group = ""
      expect(reviewer.guardian.can_review_suggested_edits_in_topic_list?).to eq(false)
    end

    it "memoizes review group membership checks on a guardian instance" do
      guardian = reviewer.guardian

      queries = track_sql_queries { 3.times { guardian.can_review_suggested_edits_in_topic_list? } }

      membership_queries =
        queries.filter do |query|
          query.include?(%("group_users"."user_id" = #{reviewer.id})) &&
            query.include?(%("groups"."id" = #{review_group.id}))
        end

      expect(membership_queries.size).to eq(1)
    end
  end

  describe "#can_review_suggested_edits_for_post?" do
    it "returns true for users in the review group" do
      expect(reviewer.guardian.can_review_suggested_edits_for_post?(first_post)).to eq(true)
    end

    it "returns true for the post author even without review group membership" do
      expect(first_post.user.guardian.can_review_suggested_edits_for_post?(first_post)).to eq(true)
    end

    it "returns true for the post author without checking review group membership" do
      author = first_post.user

      queries =
        track_sql_queries { author.guardian.can_review_suggested_edits_for_post?(first_post) }

      review_group_queries =
        queries.filter do |query|
          query.include?(%("group_users"."user_id" = #{author.id})) &&
            query.include?(%("groups"."id" = #{review_group.id}))
        end

      expect(review_group_queries).to be_empty
    end

    it "returns false when the plugin is disabled" do
      SiteSetting.suggested_edits_enabled = false
      expect(reviewer.guardian.can_review_suggested_edits_for_post?(first_post)).to eq(false)
    end

    it "returns false for anonymous users" do
      expect(Guardian.new.can_review_suggested_edits_for_post?(first_post)).to eq(false)
    end

    it "returns false for users who are neither reviewers nor the post author" do
      expect(suggester.guardian.can_review_suggested_edits_for_post?(first_post)).to eq(false)
    end

    it "returns false when the user cannot see the post" do
      private_group = Fabricate(:group)
      private_category = Fabricate(:private_category, group: private_group)
      hidden_topic = Fabricate(:topic, category: private_category)
      hidden_post = Fabricate(:post, topic: hidden_topic, post_number: 1)
      expect(reviewer.guardian.can_review_suggested_edits_for_post?(hidden_post)).to eq(false)
    end
  end

  describe "#can_review_suggested_edit?" do
    fab!(:suggestion) do
      Fabricate(
        :suggested_edit,
        post: first_post,
        user: suggester,
        base_post_version: first_post.version,
      )
    end

    it "returns true for users in the review group" do
      expect(reviewer.guardian.can_review_suggested_edit?(suggestion)).to eq(true)
    end

    it "returns true for the post author" do
      expect(first_post.user.guardian.can_review_suggested_edit?(suggestion)).to eq(true)
    end

    it "returns false for non-reviewers" do
      expect(Fabricate(:user).guardian.can_review_suggested_edit?(suggestion)).to eq(false)
    end
  end
end
