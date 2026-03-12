import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import avatar from "discourse/helpers/avatar";
import formatDate from "discourse/helpers/format-date";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import SuggestedEditChangeItem from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-change-item";
import SuggestedEditsStaleWarning from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edits-stale-warning";
import {
  applySuggestedEdit,
  dismissSuggestedEdit,
  fetchSuggestedEdits,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

export default class SuggestedEditsReviewModal extends Component {
  @service toasts;

  @tracked suggestions = [];
  @tracked currentIndex = 0;
  @tracked changeStatuses = new Map();
  @tracked loading = true;

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

  get acceptedCount() {
    return this.changes.filter(
      (c) => this.changeStatuses.get(c.id) === "accepted"
    ).length;
  }

  get applyDisabled() {
    return this.isStale || this.acceptedCount === 0;
  }

  get applyLabel() {
    const base = i18n("discourse_suggested_edits.review.apply_accepted");
    return this.acceptedCount > 0 ? `${base} (${this.acceptedCount})` : base;
  }

  get reviewSummary() {
    return i18n("discourse_suggested_edits.review.instructions");
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
  async applyAccepted() {
    const acceptedIds = this.changes
      .filter((c) => this.changeStatuses.get(c.id) === "accepted")
      .map((c) => c.id);

    if (acceptedIds.length === 0) {
      return;
    }

    try {
      await applySuggestedEdit(this.suggestion.id, acceptedIds);
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
      class="suggested-edits-review-modal"
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
                  @disabled={{this.prevDisabled}}
                  class="btn-flat btn-small"
                />
                <span class="suggested-edits-review__nav-label">
                  {{this.navLabel}}
                </span>
                <DButton
                  @action={{this.nextSuggestion}}
                  @icon="chevron-right"
                  @disabled={{this.nextDisabled}}
                  class="btn-flat btn-small"
                />
              </span>
            {{/if}}
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

          <p class="suggested-edits-review__summary">
            {{this.reviewSummary}}
          </p>

          <div class="suggested-edits-review__changes">
            {{#each this.changesWithStatus key="id" as |change|}}
              <SuggestedEditChangeItem
                @change={{change}}
                @status={{change.status}}
                @onAccept={{fn this.updateStatus change "accepted"}}
                @onReject={{fn this.updateStatus change "rejected"}}
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
                class="btn-danger suggested-edits-review-modal__discard"
              />
            </div>
            <div class="suggested-edits-review-modal__footer-primary">
              <DButton
                @action={{this.acceptAll}}
                @label="discourse_suggested_edits.review.accept_all"
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
