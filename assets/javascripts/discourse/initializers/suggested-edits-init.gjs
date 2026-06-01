import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import SuggestEditButton from "discourse/plugins/discourse-suggested-edits/discourse/components/suggest-edit-button";
import richEditorExtension from "discourse/plugins/discourse-suggested-edits/discourse/lib/rich-editor-extension";
import { SUGGEST_EDIT_ACTION } from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

function initializePlugin(api) {
  const siteSettings = api.container.lookup("service:site-settings");
  const currentUser = api.getCurrentUser();

  if (!siteSettings.suggested_edits_enabled || !currentUser) {
    return;
  }

  api.registerValueTransformer(
    "post-menu-buttons",
    ({ value: dag, context: { post, firstButtonKey } }) => {
      if (post.can_suggest_edit) {
        dag.add("suggest-edit", SuggestEditButton, {
          before: firstButtonKey,
        });
      }
    }
  );

  api.addTrackedTopicProperties(
    "pending_suggested_edit_count",
    "own_pending_suggested_edit_id"
  );

  api.addSearchSuggestion("with:suggested-edits");

  api.registerRichEditorExtension(richEditorExtension);

  api.customizeComposerText({
    actionTitle(model) {
      if (model.action === SUGGEST_EDIT_ACTION) {
        return i18n("discourse_suggested_edits.composer.action_title");
      }
    },
    saveLabel(model) {
      if (model.action === SUGGEST_EDIT_ACTION) {
        return "discourse_suggested_edits.composer.save_label";
      }
    },
  });

  api.modifyClass("controller:topic", {
    pluginId: "discourse-suggested-edits",

    subscribe() {
      this._super();

      if (!this.model?.id) {
        return;
      }

      this._suggestedEditsMessageHandler = (data) => {
        if (data.type === "suggested_edits_changed") {
          this.model.set("pending_suggested_edit_count", data.pending_count);
        }

        if (data.type === "suggested_edit_resolved") {
          this.model.set("own_pending_suggested_edit_id", null);
        }
      };

      this.messageBus.subscribe(
        `/suggested-edits/topic/${this.model.id}`,
        this._suggestedEditsMessageHandler
      );
    },

    unsubscribe() {
      this.messageBus.unsubscribe(
        "/suggested-edits/topic/*",
        this._suggestedEditsMessageHandler
      );
      this._super();
    },
  });
}

export default {
  name: "discourse-suggested-edits",
  initialize() {
    withPluginApi(initializePlugin);
  },
};
