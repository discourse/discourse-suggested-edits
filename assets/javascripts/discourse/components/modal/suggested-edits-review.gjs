import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import avatar from "discourse/helpers/avatar";
import concatClass from "discourse/helpers/concat-class";
import icon from "discourse/helpers/d-icon";
import formatDate from "discourse/helpers/format-date";
import { popupAjaxError } from "discourse/lib/ajax-error";
import KeyValueStore from "discourse/lib/key-value-store";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import SuggestedEditChangeItem from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-change-item";
import SuggestedEditsStaleWarning from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edits-stale-warning";
import {
  applySuggestedEdit,
  dismissSuggestedEdit,
  fetchSuggestedEdits,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

const VIEW_MODE_KEY = "suggested-edits-view-mode";
const store = new KeyValueStore("discourse_suggested_edits_");

export default class SuggestedEditsReviewModal extends Component {
  @service toasts;

  @tracked suggestions = [];
  @tracked currentIndex = 0;
  @tracked changeStatuses = new Map();
  @tracked editedChanges = new Map();
  @tracked editingChangeId = null;
  @tracked loading = true;
  @tracked viewMode = store.get(VIEW_MODE_KEY) || "inline";

  constructor() {
    super(...arguments);
    this.loadSuggestions();
  }

  async loadSuggestions() {
    try {
      const result = await fetchSuggestedEdits(this.args.model.post.id);
      this.suggestions = result.suggested_edits || [];
      if (this.suggestions.length > 0) {
        this.resetChangeStatuses();
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  resetChangeStatuses() {
    this.changeStatuses = new Map();
    this.editedChanges = new Map();
    this.editingChangeId = null;
  }

  get suggestion() {
    return this.suggestions[this.currentIndex];
  }

  get changes() {
    return this.suggestion?.changes || [];
  }

  get changesWithStatus() {
    return this.changes.map((c) => ({
      ...c,
      status: this.changeStatuses.get(c.id) || "pending",
      editedAfterText: this.editedChanges.get(c.id),
    }));
  }

  get isStale() {
    return this.suggestion?.status === "stale";
  }

  get hasMultiple() {
    return this.suggestions.length > 1;
  }

  get navLabel() {
    return `${this.currentIndex + 1} / ${this.suggestions.length}`;
  }

  get prevDisabled() {
    return this.currentIndex === 0;
  }

  get nextDisabled() {
    return this.currentIndex >= this.suggestions.length - 1;
  }

  get prevNavDisabled() {
    return this.prevDisabled || this.isEditing;
  }

  get nextNavDisabled() {
    return this.nextDisabled || this.isEditing;
  }

  get acceptedCount() {
    return this.changes.filter(
      (c) => this.changeStatuses.get(c.id) === "accepted"
    ).length;
  }

  get isEditing() {
    return this.editingChangeId !== null;
  }

  get applyDisabled() {
    return this.isStale || this.acceptedCount === 0 || this.isEditing;
  }

  get applyLabel() {
    const base = i18n("discourse_suggested_edits.review.apply_accepted");
    return this.acceptedCount > 0 ? `${base} (${this.acceptedCount})` : base;
  }

  get modalClass() {
    return this.viewMode === "side-by-side"
      ? "suggested-edits-review-modal suggested-edits-review-modal--side-by-side"
      : "suggested-edits-review-modal";
  }

  @action
  setInline(event) {
    event.preventDefault();
    this.viewMode = "inline";
    store.set({ key: VIEW_MODE_KEY, value: "inline" });
  }

  @action
  setSideBySide(event) {
    event.preventDefault();
    this.viewMode = "side-by-side";
    store.set({ key: VIEW_MODE_KEY, value: "side-by-side" });
  }

  @action
  updateStatus(change, status) {
    const current = this.changeStatuses.get(change.id);
    const newMap = new Map(this.changeStatuses);
    if (current === status) {
      newMap.delete(change.id);
    } else {
      newMap.set(change.id, status);
    }
    this.changeStatuses = newMap;
  }

  @action
  acceptAll() {
    const newMap = new Map();
    this.changes.forEach((c) => newMap.set(c.id, "accepted"));
    this.changeStatuses = newMap;
  }

  @action
  editChange(change) {
    this.editingChangeId = change.id;
  }

  @action
  saveEdit(change, newText) {
    const newEdited = new Map(this.editedChanges);
    newEdited.set(change.id, newText);
    this.editedChanges = newEdited;

    const newStatuses = new Map(this.changeStatuses);
    newStatuses.set(change.id, "accepted");
    this.changeStatuses = newStatuses;

    this.editingChangeId = null;
  }

  @action
  cancelEdit() {
    this.editingChangeId = null;
  }

  @action
  async applyAccepted() {
    const acceptedIds = this.changes
      .filter((c) => this.changeStatuses.get(c.id) === "accepted")
      .map((c) => c.id);

    if (acceptedIds.length === 0) {
      return;
    }

    const overrides = {};
    for (const [changeId, text] of this.editedChanges) {
      if (acceptedIds.includes(changeId)) {
        overrides[changeId] = text;
      }
    }

    try {
      await applySuggestedEdit(this.suggestion.id, acceptedIds, overrides);
      this.toasts.success({
        data: {
          message: i18n("discourse_suggested_edits.review.applied_success"),
        },
        duration: "short",
      });
      if (this.args.model.onSuccess) {
        this.args.model.onSuccess();
      }
      this.args.closeModal();
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  async dismiss() {
    try {
      await dismissSuggestedEdit(this.suggestion.id);
      this.toasts.success({
        data: {
          message: i18n("discourse_suggested_edits.review.discarded_success"),
        },
        duration: "short",
      });

      this.suggestions = this.suggestions.filter(
        (s) => s.id !== this.suggestion.id
      );
      if (this.suggestions.length === 0) {
        if (this.args.model.onSuccess) {
          this.args.model.onSuccess();
        }
        this.args.closeModal();
      } else {
        this.currentIndex = Math.min(
          this.currentIndex,
          this.suggestions.length - 1
        );
        this.resetChangeStatuses();
      }
    } catch (e) {
      popupAjaxError(e);
    }
  }

  @action
  nextSuggestion() {
    if (this.currentIndex < this.suggestions.length - 1) {
      this.currentIndex++;
      this.resetChangeStatuses();
    }
  }

  @action
  prevSuggestion() {
    if (this.currentIndex > 0) {
      this.currentIndex--;
      this.resetChangeStatuses();
    }
  }

  <template>
    <DModal
      @title={{i18n "discourse_suggested_edits.modal.review_title"}}
      @closeModal={{@closeModal}}
      class={{this.modalClass}}
    >
      <:body>
        {{#if this.loading}}
          <div class="spinner"></div>
        {{else if this.suggestion}}
          <div class="suggested-edits-review__meta">
            <span class="suggested-edits-review__author">
              {{avatar this.suggestion.user imageSize="small"}}
              <span class="suggested-edits-review__author-name username">
                {{this.suggestion.user.username}}
              </span>
            </span>
            <span class="suggested-edits-review__date">
              {{formatDate this.suggestion.created_at}}
            </span>
            {{#if this.hasMultiple}}
              <span class="suggested-edits-review__nav">
                <DButton
                  @action={{this.prevSuggestion}}
                  @icon="chevron-left"
                  @disabled={{this.prevNavDisabled}}
                  class="btn-flat btn-small"
                />
                <span class="suggested-edits-review__nav-label">
                  {{this.navLabel}}
                </span>
                <DButton
                  @action={{this.nextSuggestion}}
                  @icon="chevron-right"
                  @disabled={{this.nextNavDisabled}}
                  class="btn-flat btn-small"
                />
              </span>
            {{/if}}
            <span class="suggested-edits-review__view-modes">
              <ul class="nav nav-pills">
                <li>
                  <a
                    href
                    class={{concatClass
                      "inline-mode"
                      (if (eq this.viewMode "inline") "active")
                    }}
                    title={{i18n
                      "discourse_suggested_edits.review.view_inline"
                    }}
                    {{on "click" this.setInline}}
                  >
                    {{icon "far-square"}}
                    {{i18n "discourse_suggested_edits.review.view_inline"}}
                  </a>
                </li>
                <li>
                  <a
                    href
                    class={{concatClass
                      "side-by-side-mode"
                      (if (eq this.viewMode "side-by-side") "active")
                    }}
                    title={{i18n
                      "discourse_suggested_edits.review.view_side_by_side"
                    }}
                    {{on "click" this.setSideBySide}}
                  >
                    {{icon "table-columns"}}
                    {{i18n
                      "discourse_suggested_edits.review.view_side_by_side"
                    }}
                  </a>
                </li>
              </ul>
            </span>
          </div>

          {{#if this.suggestion.reason}}
            <p class="suggested-edits-review__reason">
              <strong>{{i18n
                  "discourse_suggested_edits.review.reason"
                }}:</strong>
              {{this.suggestion.reason}}
            </p>
          {{/if}}

          {{#if this.isStale}}
            <SuggestedEditsStaleWarning @onDismiss={{this.dismiss}} />
          {{/if}}

          <div class="suggested-edits-review__changes">
            {{#each this.changesWithStatus key="id" as |change|}}
              <SuggestedEditChangeItem
                @change={{change}}
                @status={{change.status}}
                @viewMode={{this.viewMode}}
                @onAccept={{fn this.updateStatus change "accepted"}}
                @onReject={{fn this.updateStatus change "rejected"}}
                @onEdit={{fn this.editChange change}}
                @onSaveEdit={{fn this.saveEdit change}}
                @onCancelEdit={{this.cancelEdit}}
                @isEditing={{eq this.editingChangeId change.id}}
                @isAnyEditing={{this.isEditing}}
                @editedAfterText={{change.editedAfterText}}
                @disabled={{this.isStale}}
              />
            {{/each}}
          </div>
        {{else}}
          <p>{{i18n "discourse_suggested_edits.review.no_changes_accepted"}}</p>
        {{/if}}
      </:body>
      <:footer>
        {{#if this.suggestion}}
          <div class="suggested-edits-review-modal__footer">
            <div class="suggested-edits-review-modal__footer-secondary">
              <DButton
                @action={{this.dismiss}}
                @icon="trash-can"
                @label="discourse_suggested_edits.review.discard"
                @disabled={{this.isEditing}}
                class="btn-danger suggested-edits-review-modal__discard"
              />
            </div>
            <div class="suggested-edits-review-modal__footer-primary">
              <DButton
                @action={{this.acceptAll}}
                @label="discourse_suggested_edits.review.accept_all"
                @disabled={{this.isEditing}}
                class="btn-default"
              />
              <DButton
                @action={{this.applyAccepted}}
                @translatedLabel={{this.applyLabel}}
                @disabled={{this.applyDisabled}}
                class="btn-primary"
              />
            </div>
          </div>
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
