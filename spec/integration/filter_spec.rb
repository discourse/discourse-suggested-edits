# frozen_string_literal: true

RSpec.describe "Suggested edits filters" do
  before { SiteSetting.suggested_edits_enabled = true }

  describe "TopicsFilter with:suggested-edits" do
    fab!(:topic_with_pending, :topic)
    fab!(:topic_without, :topic)
    fab!(:topic_with_dismissed, :topic)

    fab!(:post_with_pending) { Fabricate(:post, topic: topic_with_pending, post_number: 1) }
    fab!(:post_without) { Fabricate(:post, topic: topic_without, post_number: 1) }
    fab!(:post_with_dismissed) { Fabricate(:post, topic: topic_with_dismissed, post_number: 1) }

    fab!(:pending_edit) { Fabricate(:suggested_edit, post: post_with_pending, status: 0) }
    fab!(:dismissed_edit) { Fabricate(:suggested_edit, post: post_with_dismissed, status: 2) }

    def filtered_topic_ids
      TopicsFilter
        .new(guardian: Guardian.new)
        .filter_from_query_string("with:suggested-edits")
        .pluck(:id)
    end

    it "returns topics with pending suggested edits" do
      expect(filtered_topic_ids).to include(topic_with_pending.id)
    end

    it "excludes topics with no suggested edits" do
      expect(filtered_topic_ids).not_to include(topic_without.id)
    end

    it "excludes topics with only dismissed suggested edits" do
      expect(filtered_topic_ids).not_to include(topic_with_dismissed.id)
    end
  end

  describe "topics_filter_options modifier" do
    it "adds with:suggested-edits option when plugin is enabled" do
      options = TopicsFilter.option_info(Guardian.new)
      option = options.find { |o| o[:name] == "with:suggested-edits" }

      expect(option).to be_present
      expect(option).to include(
        name: "with:suggested-edits",
        description: I18n.t("discourse_suggested_edits.filter.description"),
        type: "text",
      )
    end

    it "does not add option when plugin is disabled" do
      SiteSetting.suggested_edits_enabled = false

      options = TopicsFilter.option_info(Guardian.new)
      option = options.find { |o| o[:name] == "with:suggested-edits" }

      expect(option).to be_nil
    end
  end

  describe "search advanced filter" do
    before do
      SearchIndexer.enable
      Jobs.run_immediately!
    end

    after { SearchIndexer.disable }

    it "returns only topics with pending suggested edits" do
      topic_pending =
        Fabricate(:topic, title: "A topic with pending suggested edits for search testing")
      topic_none =
        Fabricate(:topic, title: "A topic without any suggested edits for search testing")
      post_pending = Fabricate(:post, topic: topic_pending)
      Fabricate(:post, topic: topic_none)
      Fabricate(:suggested_edit, post: post_pending, status: 0)

      SearchIndexer.index(topic_pending, force: true)
      SearchIndexer.index(topic_none, force: true)

      result = Search.execute("with:suggested-edits")
      topic_ids = result.posts.map(&:topic_id)

      expect(topic_ids).to include(topic_pending.id)
      expect(topic_ids).not_to include(topic_none.id)
    end
  end
end
