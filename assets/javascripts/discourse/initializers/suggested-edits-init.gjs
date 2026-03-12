import { popupAjaxError } from "discourse/lib/ajax-error";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import SuggestEditButton from "discourse/plugins/discourse-suggested-edits/discourse/components/suggest-edit-button";
import richEditorExtension from "discourse/plugins/discourse-suggested-edits/discourse/lib/rich-editor-extension";
import {
  createSuggestedEdit,
  setSuggestEditActive,
  SUGGEST_EDIT_ACTION,
  updateSuggestedEdit,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

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

  api.modifyClass("service:composer", {
    pluginId: "discourse-suggested-edits",

    async open(opts) {
      if (opts.action === SUGGEST_EDIT_ACTION && this.model) {
        this.model.set("disableDrafts", true);
        this.skipAutoSave = true;
        this.close();
        this.skipAutoSave = false;
      }
      setSuggestEditActive(
        opts.action === SUGGEST_EDIT_ACTION,
        opts.metaData?.originalRaw
      );
      await this._super(opts);
      if (this.model?.action === SUGGEST_EDIT_ACTION) {
        this.model.set("disableDrafts", true);
      }
    },

    cancelComposer(opts) {
      if (this.model?.action === SUGGEST_EDIT_ACTION) {
        setSuggestEditActive(false);
        this.skipAutoSave = true;
        this.close();
        this.appEvents.trigger("composer:cancelled");
        this.skipAutoSave = false;
        return Promise.resolve();
      }
      return this._super(opts);
    },

    destroyDraft() {
      if (this.model?.action === SUGGEST_EDIT_ACTION) {
        return Promise.resolve();
      }
      return this._super();
    },

    save(force, options = {}) {
      if (this.model?.action === SUGGEST_EDIT_ACTION) {
        return this._saveSuggestedEdit();
      }
      return this._super(force, options);
    },

    async _saveSuggestedEdit() {
      const model = this.model;
      const meta = model.metaData || {};

      if (model.reply?.trim() === meta.originalRaw?.trim()) {
        this.toasts.error({
          data: {
            message: i18n("discourse_suggested_edits.composer.no_changes"),
          },
          duration: "short",
        });
        return;
      }

      try {
        if (meta.existingSuggestionId) {
          await updateSuggestedEdit(meta.existingSuggestionId, {
            raw: model.reply,
          });
          this.toasts.success({
            data: {
              message: i18n("discourse_suggested_edits.toast.updated"),
            },
            duration: "short",
          });
        } else {
          const result = await createSuggestedEdit({
            postId: meta.postId,
            raw: model.reply,
          });
          if (model.topic) {
            model.topic.set(
              "own_pending_suggested_edit_id",
              result.suggested_edit.id
            );
          }
          this.toasts.success({
            data: {
              message: i18n("discourse_suggested_edits.toast.created"),
            },
            duration: "short",
          });
        }

        setSuggestEditActive(false);
        this.close();
      } catch (e) {
        popupAjaxError(e);
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
