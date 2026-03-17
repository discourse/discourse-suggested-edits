# frozen_string_literal: true

module DiscourseSuggestedEdits
  class RegisterFilters
    def self.register(plugin)
      plugin.add_filter_custom_filter("with") do |scope, filter_values, guardian|
        if filter_values.include?("suggested-edits")
          scope.where(
            "topics.id IN (
              SELECT posts.topic_id FROM suggested_edits
              JOIN posts ON posts.id = suggested_edits.post_id
              WHERE suggested_edits.status = ?
            )",
            SuggestedEdit.statuses[:pending],
          )
        else
          scope
        end
      end

      plugin.register_search_advanced_filter(/with:suggested-edits/) do |posts|
        posts.where(
          "posts.topic_id IN (
            SELECT posts2.topic_id FROM suggested_edits
            JOIN posts AS posts2 ON posts2.id = suggested_edits.post_id
            WHERE suggested_edits.status = ?
          )",
          SuggestedEdit.statuses[:pending],
        )
      end

      plugin.register_modifier(:topics_filter_options) do |results, guardian|
        results << {
          name: "with:suggested-edits",
          description: I18n.t("discourse_suggested_edits.filter.description"),
          type: "text",
        }
        results
      end
    end
  end
end
