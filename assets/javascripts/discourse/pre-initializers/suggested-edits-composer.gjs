import { popupAjaxError } from "discourse/lib/ajax-error";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import {
  createSuggestedEdit,
  setSuggestEditActive,
  SUGGEST_EDIT_ACTION,
  updateSuggestedEdit,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

function isSuggestedEditAction(action) {
  return action === SUGGEST_EDIT_ACTION;
}

function isSuggestedEditModel(model) {
  return isSuggestedEditAction(model?.action);
}

export default {
  name: "discourse-suggested-edits-composer",

  // The composer service must be modified before any initializer can look it up.
  before: "inject-discourse-objects",

  initialize() {
    withPluginApi((api) => {
      api.modifyClass("service:composer", {
        pluginId: "discourse-suggested-edits",

        async open(opts) {
          if (isSuggestedEditAction(opts.action) && this.model) {
            this.model.set("disableDrafts", true);
            this.skipAutoSave = true;
            this.close();
            this.skipAutoSave = false;
          }
          setSuggestEditActive(
            isSuggestedEditAction(opts.action),
            opts.metaData?.originalRaw
          );
          await this._super(opts);
          if (isSuggestedEditModel(this.model)) {
            this.model.setProperties({
              disableDrafts: true,
              draftStatus: null,
              draftConflictUser: null,
            });
          }
        },

        cancelComposer(opts) {
          if (isSuggestedEditModel(this.model)) {
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
          if (isSuggestedEditModel(this.model)) {
            return Promise.resolve();
          }
          return this._super();
        },

        _saveDraft(showToast = false) {
          if (isSuggestedEditModel(this.model)) {
            return Promise.resolve();
          }

          return this._super(showToast);
        },

        save(force, options = {}) {
          if (isSuggestedEditModel(this.model)) {
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
                reason: meta.reason,
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
                reason: meta.reason,
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
    });
  },
};
