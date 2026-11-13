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
import { afterRender } from "discourse/lib/decorators";
import KeyValueStore from "discourse/lib/key-value-store";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import SuggestedEditChangeItem from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-change-item";
import SuggestedEditContext from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-context";
import SuggestedEditRenderedPreview, {
  unavailableNotice,
} from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-rendered-preview";
import SuggestedEditsStaleWarning from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edits-stale-warning";
import sanitizeRenderedPreview from "discourse/plugins/discourse-suggested-edits/discourse/lib/sanitize-rendered-preview";
import {
  applySuggestedEdit,
  dismissSuggestedEdit,
  fetchSuggestedEdit,
  fetchSuggestedEdits,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

const VIEW_MODE_KEY = "suggested-edits-view-mode";
const VIEW_MODES = ["inline", "side-by-side", "source"];
const RESOLVED_NOTICES = {
  applied: "discourse_suggested_edits.review.resolved.applied",
  dismissed: "discourse_suggested_edits.review.resolved.dismissed",
  withdrawn: "discourse_suggested_edits.review.resolved.withdrawn",
};
const store = new KeyValueStore("discourse_suggested_edits_");

export default class SuggestedEditsReviewModal extends Component {
  static RENDERED_PREVIEW_TIMEOUT = 20000;

  @service a11y;
  @service site;
  @service toasts;

  @tracked suggestions = [];
  @tracked currentIndex = 0;
  @tracked changeStatuses = new Map();
  @tracked editedChanges = new Map();
  @tracked editingChangeId = null;
  @tracked loading = true;
  @tracked renderedPreviews = new Map();
  @tracked expandedGaps = new Map();
  @tracked submitting = false;
  @tracked viewMode = this.#initialViewMode();

  #previewRequests = new Map();

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
        this.loadRenderedPreview();
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.loading = false;
    }
  }

  async loadRenderedPreview() {
    const id = this.suggestion?.id;
    const cached = this.renderedPreviews.get(id);
    if (!id || (cached && (cached.loading || !cached.failed))) {
      return;
    }

    const request = {};
    this.#previewRequests.set(id, request);
    // A failed preview keeps its notice and retry control while it reloads.
    this.#setRenderedPreview(id, { ...cached, loading: true });

    let suggestion;
    let preview;
    try {
      const result = await fetchSuggestedEdit(id, {
        includeRenderedPreview: true,
        timeout: this.constructor.RENDERED_PREVIEW_TIMEOUT,
      });
      suggestion = result.suggested_edit;
      preview = await sanitizeRenderedPreview(suggestion?.rendered_preview);
    } catch (error) {
      preview = {
        available: false,
        failed: true,
        unavailableReason:
          error?.jqXHR?.status === 429 ? "rate_limited" : "error",
      };
    }

    if (
      this.isDestroying ||
      this.isDestroyed ||
      this.#previewRequests.get(id) !== request
    ) {
      return;
    }

    const focusWasInReview = Boolean(
      document.activeElement?.closest(".suggested-edits-review-modal")
    );
    const focusWasOnRetry = Boolean(
      document.activeElement?.closest(".suggested-edit-preview__retry")
    );
    const refreshed = suggestion && this.#refreshSuggestion(suggestion);
    this.#setRenderedPreview(id, preview);

    if (this.suggestion?.id !== id) {
      return;
    }

    // Decisions made against a replaced or unappliable record can't be applied.
    if (refreshed || this.isUnsupported) {
      this.resetChangeStatuses();
    }

    if (preview.available && focusWasOnRetry) {
      this._restoreLostFocus();
    }

    let notice;
    if (refreshed) {
      notice = this.#refreshNotice();
    } else if (preview.failed || this.isUnsupported) {
      notice = unavailableNotice(preview.unavailableReason);
    }

    if (notice) {
      this.a11y.announce(notice, "polite");
      if (focusWasInReview) {
        this._restoreLostFocus();
      }
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
      renderedPreview: this.renderedPreview?.changes?.get(c.id),
    }));
  }

  get contextGaps() {
    const gaps = this.renderedPreview?.gaps;
    if (!this.renderedPreview?.available || !Array.isArray(gaps)) {
      return null;
    }

    const ids = new Set();
    const boundaries = new Set();
    for (const gap of gaps) {
      const index =
        gap.before_change_id === null
          ? this.changes.length
          : this.changes.findIndex(
              (change) => change.id === gap.before_change_id
            );
      const afterId = index > 0 ? this.changes[index - 1].id : null;
      if (
        index < 0 ||
        typeof gap.id !== "string" ||
        !gap.id ||
        typeof gap.raw !== "string" ||
        gap.after_change_id !== afterId ||
        ids.has(gap.id) ||
        boundaries.has(gap.before_change_id)
      ) {
        return null;
      }
      ids.add(gap.id);
      boundaries.add(gap.before_change_id);
    }

    return gaps;
  }

  get hasContextGaps() {
    return this.contextGaps !== null;
  }

  get reviewItems() {
    const gaps = new Map(
      (this.contextGaps ?? []).map((gap) => [gap.before_change_id, gap])
    );
    const expanded = this.expandedGaps.get(this.suggestion.id);
    const items = [];
    const addGap = (gap) => {
      if (gap) {
        items.push({
          key: `gap-${gap.id}`,
          gap,
          expanded: expanded?.has(gap.id),
        });
      }
    };

    this.changesWithStatus.forEach((change, index) => {
      addGap(gaps.get(change.id));
      items.push({ key: `change-${change.id}`, change, index });
    });
    addGap(gaps.get(null));
    return items;
  }

  get isStale() {
    return this.suggestion?.status === "stale";
  }

  get isResolved() {
    return Object.hasOwn(RESOLVED_NOTICES, this.suggestion?.status);
  }

  get isUnsupported() {
    return this.renderedPreview?.unavailableReason === "unsupported_post";
  }

  get decisionsDisabled() {
    return (
      this.suggestion?.status !== "pending" ||
      this.isUnsupported ||
      this.submitting
    );
  }

  get resolvedNotice() {
    return i18n(RESOLVED_NOTICES[this.suggestion.status]);
  }

  get renderedPreview() {
    return this.renderedPreviews.get(this.suggestion?.id);
  }

  get showPreviewStatus() {
    const preview = this.renderedPreview;
    return preview?.loading || preview?.failed || preview?.unavailableReason;
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
    return this.prevDisabled || this.isEditing || this.submitting;
  }

  get nextNavDisabled() {
    return this.nextDisabled || this.isEditing || this.submitting;
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
    return this.decisionsDisabled || this.acceptedCount === 0 || this.isEditing;
  }

  get discardDisabled() {
    return this.isResolved || this.isEditing || this.submitting;
  }

  get acceptAllDisabled() {
    return this.decisionsDisabled || this.isEditing;
  }

  get applyLabel() {
    const base = i18n("discourse_suggested_edits.review.apply_accepted");
    return this.acceptedCount > 0 ? `${base} (${this.acceptedCount})` : base;
  }

  // Two columns are too narrow on mobile, where the rendered view stays inline.
  get effectiveViewMode() {
    if (this.site.mobileView && this.viewMode === "side-by-side") {
      return "inline";
    }
    return this.viewMode;
  }

  get changeViewMode() {
    return this.site.mobileView || this.effectiveViewMode === "inline"
      ? "inline"
      : "side-by-side";
  }

  get modalClass() {
    return this.effectiveViewMode === "inline"
      ? "suggested-edits-review-modal"
      : "suggested-edits-review-modal suggested-edits-review-modal--side-by-side";
  }

  @action
  toggleGap(gap) {
    const id = this.suggestion.id;
    const expanded = new Set(this.expandedGaps.get(id));
    if (expanded.has(gap.id)) {
      expanded.delete(gap.id);
    } else {
      expanded.add(gap.id);
    }
    const gaps = new Map(this.expandedGaps);
    gaps.set(id, expanded);
    this.expandedGaps = gaps;
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
  setSource(event) {
    event.preventDefault();
    this.viewMode = "source";
    store.set({ key: VIEW_MODE_KEY, value: "source" });
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
    if (newText === change.after_text) {
      newEdited.delete(change.id);
    } else {
      newEdited.set(change.id, newText);
    }
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
  retryRenderedPreview() {
    return this.loadRenderedPreview();
  }

  @action
  async applyAccepted() {
    if (this.submitting) {
      return;
    }

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

    const id = this.suggestion.id;
    this.submitting = true;
    try {
      await applySuggestedEdit(id, acceptedIds, overrides);
      this.args.model.onSuccess?.();
      if (this.isDestroying || this.isDestroyed) {
        return;
      }

      this.toasts.success({
        data: {
          message: i18n("discourse_suggested_edits.review.applied_success"),
        },
        duration: "short",
      });
      this.args.closeModal();
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.submitting = false;
    }
  }

  @action
  async dismiss() {
    if (this.submitting) {
      return;
    }

    const id = this.suggestion.id;
    this.submitting = true;
    try {
      await dismissSuggestedEdit(id);
      this.args.model.onSuccess?.();
      if (this.isDestroying || this.isDestroyed) {
        return;
      }

      this.toasts.success({
        data: {
          message: i18n("discourse_suggested_edits.review.discarded_success"),
        },
        duration: "short",
      });

      this.suggestions = this.suggestions.filter((s) => s.id !== id);
      if (this.suggestions.length === 0) {
        this.args.closeModal();
      } else {
        this.currentIndex = Math.min(
          this.currentIndex,
          this.suggestions.length - 1
        );
        this.resetChangeStatuses();
        this.loadRenderedPreview();
        this._restoreLostFocus();
      }
    } catch (e) {
      popupAjaxError(e);
    } finally {
      this.submitting = false;
    }
  }

  @action
  nextSuggestion() {
    if (this.currentIndex < this.suggestions.length - 1) {
      this.currentIndex++;
      this.resetChangeStatuses();
      this.loadRenderedPreview();
    }
  }

  @action
  prevSuggestion() {
    if (this.currentIndex > 0) {
      this.currentIndex--;
      this.resetChangeStatuses();
      this.loadRenderedPreview();
    }
  }

  #initialViewMode() {
    const stored = store.get(VIEW_MODE_KEY);
    if (VIEW_MODES.includes(stored)) {
      return stored;
    }

    return this.site.mobileView ? "inline" : "side-by-side";
  }

  // Some status changes keep `updated_at`, so a new status also counts.
  #refreshSuggestion(updated) {
    const index = this.suggestions.findIndex((s) => s.id === updated.id);
    const current = this.suggestions[index];
    if (!current) {
      return false;
    }

    const updatedAt = Date.parse(updated.updated_at);
    const currentAt = Date.parse(current.updated_at);
    const changed =
      updatedAt > currentAt ||
      (updatedAt === currentAt && updated.status !== current.status);
    if (!changed) {
      return false;
    }

    const expanded = new Map(this.expandedGaps);
    expanded.delete(updated.id);
    this.expandedGaps = expanded;
    const suggestions = [...this.suggestions];
    suggestions[index] = updated;
    this.suggestions = suggestions;
    return true;
  }

  #refreshNotice() {
    if (this.isResolved) {
      return this.resolvedNotice;
    }

    return i18n(
      this.isStale
        ? "discourse_suggested_edits.review.stale_warning"
        : "discourse_suggested_edits.review.revised"
    );
  }

  #setRenderedPreview(id, preview) {
    const previews = new Map(this.renderedPreviews);
    previews.set(id, preview);
    this.renderedPreviews = previews;
  }

  // Removing the focused control moves focus to the body, and disabling it
  // does too once the browser next renders.
  @afterRender
  _restoreLostFocus() {
    const active = document.activeElement;
    if (active === document.body || active?.disabled) {
      const modal = document.querySelector(".suggested-edits-review-modal");
      (
        modal?.querySelector(
          ".suggested-edits-review-modal__resolved-notice, .suggested-edits-stale-warning, .suggested-edit-preview__fallback, .suggested-edit-preview__body"
        ) ?? modal?.querySelector(".d-modal__body")
      )?.focus();
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
          <div class="suggested-edits-review-modal__meta">
            <span class="suggested-edits-review-modal__author">
              {{avatar this.suggestion.user imageSize="small"}}
              <span class="suggested-edits-review-modal__author-name username">
                {{this.suggestion.user.username}}
              </span>
            </span>
            <span class="suggested-edits-review-modal__date">
              {{formatDate this.suggestion.created_at}}
            </span>
            {{#if this.hasMultiple}}
              <span class="suggested-edits-review-modal__nav">
                <DButton
                  @action={{this.prevSuggestion}}
                  @icon="chevron-left"
                  @disabled={{this.prevNavDisabled}}
                  class="btn-flat btn-small"
                />
                <span class="suggested-edits-review-modal__nav-label">
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
            <span class="suggested-edits-review-modal__view-modes">
              <ul class="nav nav-pills">
                <li>
                  <a
                    aria-current={{if
                      (eq this.effectiveViewMode "inline")
                      "true"
                    }}
                    aria-label={{i18n
                      "discourse_suggested_edits.review.view_inline_title"
                    }}
                    class={{concatClass
                      "inline-mode"
                      (if (eq this.effectiveViewMode "inline") "active")
                    }}
                    href
                    title={{i18n
                      "discourse_suggested_edits.review.view_inline_title"
                    }}
                    {{on "click" this.setInline}}
                  >
                    {{icon "far-square"}}
                    {{i18n "discourse_suggested_edits.review.view_inline"}}
                  </a>
                </li>
                {{#unless this.site.mobileView}}
                  <li>
                    <a
                      aria-current={{if
                        (eq this.viewMode "side-by-side")
                        "true"
                      }}
                      aria-label={{i18n
                        "discourse_suggested_edits.review.view_side_by_side_title"
                      }}
                      class={{concatClass
                        "side-by-side-mode"
                        (if (eq this.viewMode "side-by-side") "active")
                      }}
                      href
                      title={{i18n
                        "discourse_suggested_edits.review.view_side_by_side_title"
                      }}
                      {{on "click" this.setSideBySide}}
                    >
                      {{icon "table-columns"}}
                      {{i18n
                        "discourse_suggested_edits.review.view_side_by_side"
                      }}
                    </a>
                  </li>
                {{/unless}}
                <li>
                  <a
                    aria-current={{if (eq this.viewMode "source") "true"}}
                    aria-label={{i18n
                      "discourse_suggested_edits.review.view_source_title"
                    }}
                    class={{concatClass
                      "source-mode"
                      (if (eq this.viewMode "source") "active")
                    }}
                    href
                    title={{i18n
                      "discourse_suggested_edits.review.view_source_title"
                    }}
                    {{on "click" this.setSource}}
                  >
                    {{icon "code"}}
                    {{i18n "discourse_suggested_edits.review.view_source"}}
                  </a>
                </li>
              </ul>
            </span>
          </div>

          {{#if this.suggestion.reason}}
            <p class="suggested-edits-review-modal__reason">
              <strong>{{i18n
                  "discourse_suggested_edits.review.reason"
                }}:</strong>
              {{this.suggestion.reason}}
            </p>
          {{/if}}

          {{#if this.isStale}}
            <SuggestedEditsStaleWarning
              @disabled={{this.discardDisabled}}
              @onDismiss={{this.dismiss}}
            />
          {{else if this.isResolved}}
            <div
              class="suggested-edits-review-modal__resolved-notice alert alert-info"
              tabindex="-1"
            >
              {{this.resolvedNotice}}
            </div>
          {{/if}}

          {{#if this.showPreviewStatus}}
            <SuggestedEditRenderedPreview
              @loading={{this.renderedPreview.loading}}
              @onRetry={{this.retryRenderedPreview}}
              @preview={{this.renderedPreview}}
            />
          {{/if}}

          <div class="suggested-edits-review-modal__changes">
            {{#each this.reviewItems key="key" as |item|}}
              {{#if item.gap}}
                <SuggestedEditContext
                  @gap={{item.gap}}
                  @expanded={{item.expanded}}
                  @onToggle={{fn this.toggleGap item.gap}}
                  @viewMode={{this.effectiveViewMode}}
                />
              {{else}}
                <SuggestedEditChangeItem
                  @change={{item.change}}
                  @index={{item.index}}
                  @status={{item.change.status}}
                  @viewMode={{this.effectiveViewMode}}
                  @sourceViewMode={{this.changeViewMode}}
                  @renderedPreview={{item.change.renderedPreview}}
                  @onAccept={{fn this.updateStatus item.change "accepted"}}
                  @onReject={{fn this.updateStatus item.change "rejected"}}
                  @onEdit={{fn this.editChange item.change}}
                  @onSaveEdit={{fn this.saveEdit item.change}}
                  @onCancelEdit={{this.cancelEdit}}
                  @isEditing={{eq this.editingChangeId item.change.id}}
                  @isAnyEditing={{this.isEditing}}
                  @editedAfterText={{item.change.editedAfterText}}
                  @disabled={{this.decisionsDisabled}}
                  @suppressContext={{this.hasContextGaps}}
                />
              {{/if}}
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
                @disabled={{this.discardDisabled}}
                class="btn-danger suggested-edits-review-modal__discard"
              />
            </div>
            <div class="suggested-edits-review-modal__footer-primary">
              <DButton
                @action={{this.acceptAll}}
                @label="discourse_suggested_edits.review.accept_all"
                @disabled={{this.acceptAllDisabled}}
                class="btn-default suggested-edits-review-modal__accept-all"
              />
              <DButton
                @action={{this.applyAccepted}}
                @translatedLabel={{this.applyLabel}}
                @disabled={{this.applyDisabled}}
                class="btn-primary suggested-edits-review-modal__apply"
              />
            </div>
          </div>
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
