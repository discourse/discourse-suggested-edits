# frozen_string_literal: true

RSpec.describe DiscourseSuggestedEdits::SuggestionsController do
  fab!(:category)
  fab!(:tag)
  fab!(:suggest_group, :group)
  fab!(:review_group, :group)
  fab!(:suggester) { Fabricate(:user, groups: [suggest_group]) }
  fab!(:reviewer) { Fabricate(:user, groups: [review_group]) }
  fab!(:topic) { Fabricate(:topic, category: category, tags: [tag]) }
  fab!(:first_post) do
    Fabricate(:post, topic: topic, post_number: 1, raw: "Original content here.\n")
  end

  before do
    SiteSetting.suggested_edits_enabled = true
    SiteSetting.suggested_edits_suggest_group = suggest_group.id.to_s
    SiteSetting.suggested_edits_review_group = review_group.id.to_s
    SiteSetting.suggested_edits_included_categories = category.id.to_s
  end

  def create_suggestion!(user:, raw: "Suggested content.\n", reason: nil, post: first_post)
    suggestion =
      Fabricate(
        :suggested_edit,
        post: post,
        user: user,
        raw_suggestion: raw,
        base_post_version: post.version,
        reason: reason,
      )

    DiscourseSuggestedEdits::ChangeExtractor
      .call(original_raw: post.raw, new_raw: raw)
      .each { |change| Fabricate(:suggested_edit_change, suggested_edit: suggestion, **change) }

    suggestion
  end

  def review_update(messages)
    messages.find { |message| message.data[:type] == "suggested_edits_changed" }
  end

  def resolved_update(messages)
    messages.find { |message| message.data[:type] == "suggested_edit_resolved" }
  end

  describe "POST /suggested-edits/suggestions" do
    it "requires login" do
      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: "New content",
           }

      expect(response.status).to eq(403)
    end

    it "creates a suggestion for authorized users" do
      sign_in(suggester)

      messages =
        MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") do
          post "/suggested-edits/suggestions.json",
               params: {
                 post_id: first_post.id,
                 raw: "New content here.\n",
                 reason: "Improved wording",
               }
        end

      expect(response.status).to eq(201)
      json = response.parsed_body
      expect(json.dig("suggested_edit", "raw_suggestion")).to eq("New content here.\n")
      expect(json.dig("suggested_edit", "reason")).to eq("Improved wording")
      expect(json.dig("suggested_edit", "changes").length).to eq(1)

      expect(messages.length).to eq(1)
      expect(review_update(messages).data[:pending_count]).to eq(1)
      expect(review_update(messages).user_ids).to eq([first_post.user_id])
      expect(review_update(messages).group_ids).to match_array(
        [review_group.id, Group::AUTO_GROUPS[:admins]],
      )
      expect(review_update(messages).user_ids).not_to include(suggester.id)
    end

    it "rejects if raw is same as original" do
      sign_in(suggester)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: first_post.raw,
           }

      expect(response.status).to eq(400)
    end

    it "rejects unauthorized users" do
      sign_in(Fabricate(:user))

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: "New content",
           }

      expect(response.status).to eq(403)
    end

    it "rejects duplicate pending suggestions" do
      sign_in(suggester)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: "New content.\n",
           }
      expect(response.status).to eq(201)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: "Another new content.\n",
           }

      expect(response.status).to eq(400)
    end

    it "rejects oversized raw payloads" do
      sign_in(suggester)
      oversized_raw = "a" * (SiteSetting.max_post_length + 1)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: oversized_raw,
           }

      expect(response.status).to eq(400)
      expect(response.parsed_body["errors"]).to include(
        "Raw #{
          I18n.t(
            "errors.messages.too_long_validation",
            count: SiteSetting.max_post_length,
            length: oversized_raw.length,
          )
        }",
      )
    end

    it "rejects hidden posts with not found" do
      private_access_group = Fabricate(:group)
      private_category = Fabricate(:private_category, group: private_access_group)
      hidden_topic = Fabricate(:topic, category: private_category)
      hidden_post =
        Fabricate(:post, topic: hidden_topic, post_number: 1, raw: "Restricted content.\n")
      outsider = Fabricate(:user, groups: [suggest_group])

      SiteSetting.suggested_edits_included_categories = "#{category.id}|#{private_category.id}"

      sign_in(outsider)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: hidden_post.id,
             raw: "Updated restricted content.\n",
           }

      expect(response.status).to eq(404)
    end
  end

  describe "create and revise rate limits" do
    before do
      RateLimiter.enable
      SiteSetting.suggested_edits_max_creates_per_minute = 1
      SiteSetting.suggested_edits_max_revisions_per_minute = 1
    end

    after { RateLimiter.disable }

    it "rate limits suggestion creation per user" do
      limited_user = Fabricate(:user, groups: [suggest_group])
      second_topic = Fabricate(:topic, category: category, tags: [tag])
      second_post = Fabricate(:post, topic: second_topic, post_number: 1, raw: "Second post.\n")

      sign_in(limited_user)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: first_post.id,
             raw: "First suggestion.\n",
           }
      expect(response.status).to eq(201)

      post "/suggested-edits/suggestions.json",
           params: {
             post_id: second_post.id,
             raw: "Second suggestion.\n",
           }

      expect(response.status).to eq(429)
      expect(response.headers["Retry-After"]).to be_present
    end

    it "rate limits suggestion revisions per user" do
      limited_user = Fabricate(:user, groups: [suggest_group])
      suggestion = create_suggestion!(user: limited_user)

      sign_in(limited_user)

      put "/suggested-edits/suggestions/#{suggestion.id}.json", params: { raw: "First revision.\n" }
      expect(response.status).to eq(200)

      put "/suggested-edits/suggestions/#{suggestion.id}.json",
          params: {
            raw: "Second revision.\n",
          }

      expect(response.status).to eq(429)
      expect(response.headers["Retry-After"]).to be_present
    end
  end

  describe "PUT /suggested-edits/suggestions/:id" do
    fab!(:suggestion) { create_suggestion!(user: suggester) }

    it "allows the suggester to revise" do
      sign_in(suggester)

      put "/suggested-edits/suggestions/#{suggestion.id}.json",
          params: {
            raw: "Revised content.\n",
          }

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("suggested_edit", "raw_suggestion")).to eq(
        "Revised content.\n",
      )
    end

    it "rejects revision by other users" do
      sign_in(reviewer)

      put "/suggested-edits/suggestions/#{suggestion.id}.json", params: { raw: "Hacked content" }

      expect(response.status).to eq(403)
    end

    it "rejects revision if suggestion is no longer pending" do
      suggestion.update!(status: :applied)
      sign_in(suggester)

      put "/suggested-edits/suggestions/#{suggestion.id}.json",
          params: {
            raw: "Revised content.\n",
          }

      expect(response.status).to eq(403)
    end

    it "rejects overlong reasons" do
      sign_in(suggester)

      put "/suggested-edits/suggestions/#{suggestion.id}.json",
          params: {
            raw: "Revised content.\n",
            reason: "a" * 1001,
          }

      expect(response.status).to eq(400)
      expect(response.parsed_body["errors"].first).to include("too long")
    end
  end

  describe "DELETE /suggested-edits/suggestions/:id" do
    fab!(:suggestion) { create_suggestion!(user: suggester) }

    it "allows the suggester to withdraw" do
      sign_in(suggester)

      messages =
        MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") do
          delete "/suggested-edits/suggestions/#{suggestion.id}.json"
        end

      expect(response.status).to eq(204)
      expect(suggestion.reload).to be_withdrawn
      expect(suggestion.edit_changes.count).to eq(1)
      expect(messages.length).to eq(2)
      expect(review_update(messages).data[:pending_count]).to eq(0)
      expect(review_update(messages).user_ids).to eq([first_post.user_id])
      expect(review_update(messages).group_ids).to match_array(
        [review_group.id, Group::AUTO_GROUPS[:admins]],
      )
      expect(resolved_update(messages).user_ids).to eq([suggester.id])
      expect(resolved_update(messages).group_ids).to be_nil
    end

    it "rejects withdrawal by other users" do
      sign_in(reviewer)

      delete "/suggested-edits/suggestions/#{suggestion.id}.json"

      expect(response.status).to eq(403)
    end
  end

  describe "GET /suggested-edits/suggestions" do
    fab!(:suggestion) { create_suggestion!(user: suggester) }

    it "lists pending suggestions for reviewers" do
      sign_in(reviewer)

      get "/suggested-edits/suggestions.json", params: { post_id: first_post.id }

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("suggested_edits").length).to eq(1)
    end

    it "lists own suggestions for suggesters" do
      sign_in(suggester)

      get "/suggested-edits/suggestions.json", params: { post_id: first_post.id }

      expect(response.status).to eq(200)
      expect(response.parsed_body.fetch("suggested_edits").length).to eq(1)
    end
  end

  describe "GET /suggested-edits/suggestions/:id" do
    fab!(:suggestion) { create_suggestion!(user: suggester) }

    it "returns the suggestion for reviewers" do
      sign_in(reviewer)

      get "/suggested-edits/suggestions/#{suggestion.id}.json"

      expect(response.status).to eq(200)
      expect(response.parsed_body.dig("suggested_edit", "id")).to eq(suggestion.id)
      expect(response.parsed_body.dig("suggested_edit", "changes")).to be_present
    end

    it "returns the suggestion for the suggester" do
      sign_in(suggester)

      get "/suggested-edits/suggestions/#{suggestion.id}.json"

      expect(response.status).to eq(200)
    end

    it "serializes preview and expanded context fields" do
      context_post =
        Fabricate(
          :post,
          topic: Fabricate(:topic, category: category, tags: [tag]),
          post_number: 1,
          raw:
            "Lead paragraph before the change.\n\nOriginal content here.\n\nTrailing paragraph after the change.\n",
        )
      context_suggestion =
        Fabricate(
          :suggested_edit,
          post: context_post,
          user: suggester,
          raw_suggestion:
            "Lead paragraph before the change.\n\nUpdated content here.\n\nTrailing paragraph after the change.\n",
          base_post_version: context_post.version,
        )

      DiscourseSuggestedEdits::ChangeExtractor
        .call(original_raw: context_post.raw, new_raw: context_suggestion.raw_suggestion)
        .each do |change|
          Fabricate(:suggested_edit_change, suggested_edit: context_suggestion, **change)
        end

      sign_in(reviewer)

      get "/suggested-edits/suggestions/#{context_suggestion.id}.json"

      expect(response.status).to eq(200)
      change = response.parsed_body.dig("suggested_edit", "changes", 0)
      expect(change["preview_context_before"]).to include("Lead paragraph before the change.")
      expect(change["preview_context_after"]).to include("Trailing paragraph after the change.")
      expect(change["context_before"]).to include("Lead paragraph before the change.")
      expect(change["context_after"]).to include("Trailing paragraph after the change.")
    end
  end

  describe "restricted topic access" do
    fab!(:private_access_group, :group)
    fab!(:private_category) { Fabricate(:private_category, group: private_access_group) }
    fab!(:private_author) { Fabricate(:user, groups: [private_access_group]) }
    fab!(:private_topic) { Fabricate(:topic, category: private_category) }
    fab!(:private_post) do
      Fabricate(
        :post,
        topic: private_topic,
        user: private_author,
        post_number: 1,
        raw: "Restricted original content.\n",
      )
    end
    fab!(:private_suggester) { Fabricate(:user, groups: [suggest_group, private_access_group]) }
    fab!(:private_reviewer) { Fabricate(:user, groups: [review_group, private_access_group]) }

    before do
      SiteSetting.suggested_edits_included_categories = "#{category.id}|#{private_category.id}"
    end

    it "returns not found when a suggester loses access to their suggestion" do
      suggestion =
        create_suggestion!(
          user: private_suggester,
          raw: "Restricted updated content.\n",
          post: private_post,
        )

      GroupUser.where(group: private_access_group, user: private_suggester).delete_all
      sign_in(private_suggester)

      get "/suggested-edits/suggestions/#{suggestion.id}.json"
      expect(response.status).to eq(404)

      put "/suggested-edits/suggestions/#{suggestion.id}.json",
          params: {
            raw: "Another restricted update.\n",
          }
      expect(response.status).to eq(404)
    end

    it "returns not found when a reviewer loses access to a suggestion" do
      suggestion =
        create_suggestion!(
          user: private_suggester,
          raw: "Restricted updated content.\n",
          post: private_post,
        )

      GroupUser.where(group: private_access_group, user: private_reviewer).delete_all
      sign_in(private_reviewer)

      get "/suggested-edits/suggestions/#{suggestion.id}.json"
      expect(response.status).to eq(404)

      put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
          params: {
            accepted_change_ids: suggestion.edit_changes.pluck(:id),
          }
      expect(response.status).to eq(404)
    end
  end

  describe "PUT /suggested-edits/suggestions/:id/apply" do
    fab!(:suggestion) { create_suggestion!(user: suggester, raw: "New content here.\n") }

    it "applies accepted changes and attributes the edit to the suggester" do
      sign_in(reviewer)
      change_ids = suggestion.edit_changes.pluck(:id)

      messages =
        MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") do
          put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
              params: {
                accepted_change_ids: change_ids,
              }
        end

      expect(response.status).to eq(204)
      expect(suggestion.reload).to be_applied
      expect(first_post.reload.raw).to eq("New content here.")
      expect(first_post.last_editor_id).to eq(suggester.id)
      expect(messages.length).to eq(2)
      expect(review_update(messages).data[:pending_count]).to eq(0)
      expect(review_update(messages).user_ids).to eq([first_post.user_id])
      expect(review_update(messages).group_ids).to match_array(
        [review_group.id, Group::AUTO_GROUPS[:admins]],
      )
      expect(resolved_update(messages).user_ids).to eq([suggester.id])
      expect(resolved_update(messages).group_ids).to be_nil
    end

    it "allows post author to apply" do
      sign_in(first_post.user)

      put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
          params: {
            accepted_change_ids: suggestion.edit_changes.pluck(:id),
          }

      expect(response.status).to eq(204)
    end

    it "rejects apply from non-reviewers" do
      sign_in(Fabricate(:user))

      put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
          params: {
            accepted_change_ids: suggestion.edit_changes.pluck(:id),
          }

      expect(response.status).to eq(403)
    end

    it "rejects apply when no changes are selected" do
      sign_in(reviewer)

      put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
          params: {
            accepted_change_ids: [],
          }

      expect(response.status).to eq(400)
    end

    it "rejects apply when the suggestion is stale" do
      suggestion.post.update_column(:version, suggestion.post.version + 1)
      sign_in(reviewer)

      put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
          params: {
            accepted_change_ids: suggestion.edit_changes.pluck(:id),
          }

      expect(response.status).to eq(409)
      expect(suggestion.reload).to be_stale
    end

    it "rejects apply when the suggestion is no longer pending" do
      suggestion.update!(status: :dismissed)
      sign_in(reviewer)

      put "/suggested-edits/suggestions/#{suggestion.id}/apply.json",
          params: {
            accepted_change_ids: suggestion.edit_changes.pluck(:id),
          }

      expect(response.status).to eq(409)
    end
  end

  describe "PUT /suggested-edits/suggestions/:id/dismiss" do
    fab!(:suggestion) { create_suggestion!(user: suggester) }

    it "dismisses the suggestion and publishes a MessageBus update" do
      sign_in(reviewer)

      messages =
        MessageBus.track_publish("/suggested-edits/topic/#{topic.id}") do
          put "/suggested-edits/suggestions/#{suggestion.id}/dismiss.json"
        end

      expect(response.status).to eq(204)
      expect(suggestion.reload).to be_dismissed
      expect(messages.length).to eq(2)
      expect(review_update(messages).data[:pending_count]).to eq(0)
      expect(review_update(messages).user_ids).to eq([first_post.user_id])
      expect(review_update(messages).group_ids).to match_array(
        [review_group.id, Group::AUTO_GROUPS[:admins]],
      )
      expect(resolved_update(messages).user_ids).to eq([suggester.id])
      expect(resolved_update(messages).group_ids).to be_nil
    end

    it "rejects dismiss from non-reviewers" do
      sign_in(Fabricate(:user))

      put "/suggested-edits/suggestions/#{suggestion.id}/dismiss.json"

      expect(response.status).to eq(403)
    end

    it "rejects dismiss when the suggestion is no longer pending" do
      suggestion.update!(status: :applied)
      sign_in(reviewer)

      put "/suggested-edits/suggestions/#{suggestion.id}/dismiss.json"

      expect(response.status).to eq(409)
    end
  end
end
