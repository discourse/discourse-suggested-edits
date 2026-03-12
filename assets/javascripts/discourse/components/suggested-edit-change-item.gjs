import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import DButton from "discourse/components/d-button";

export default class SuggestedEditChangeItem extends Component {
  static CONTEXT_STEP = 220;

  @tracked visibleBeforeLength = 0;
  @tracked visibleAfterLength = 0;

  constructor() {
    super(...arguments);
    this.visibleBeforeLength =
      this.args.change.preview_context_before?.length || 0;
    this.visibleAfterLength =
      this.args.change.preview_context_after?.length || 0;
  }

  get isAccepted() {
    return this.args.status === "accepted";
  }

  get isRejected() {
    return this.args.status === "rejected";
  }

  get itemClass() {
    if (this.isAccepted) {
      return "suggested-edit-change-item suggested-edit-change-item--accepted";
    }
    if (this.isRejected) {
      return "suggested-edit-change-item suggested-edit-change-item--rejected";
    }
    return "suggested-edit-change-item suggested-edit-change-item--pending";
  }

  get visibleContextBefore() {
    if (!this.visibleBeforeLength) {
      return "";
    }

    return this.args.change.context_before.slice(-this.visibleBeforeLength);
  }

  get visibleContextAfter() {
    if (!this.visibleAfterLength) {
      return "";
    }

    return this.args.change.context_after.slice(0, this.visibleAfterLength);
  }

  get showVisibleContextBefore() {
    return this.visibleContextBefore.length > 0;
  }

  get showVisibleContextAfter() {
    return this.visibleContextAfter.length > 0;
  }

  get hasMoreContextBefore() {
    return this.args.change.context_before.length > this.visibleBeforeLength;
  }

  get hasMoreContextAfter() {
    return this.args.change.context_after.length > this.visibleAfterLength;
  }

  @action
  expandBefore() {
    this.visibleBeforeLength = Math.min(
      this.args.change.context_before.length,
      this.visibleBeforeLength + this.constructor.CONTEXT_STEP
    );
  }

  @action
  expandAfter() {
    this.visibleAfterLength = Math.min(
      this.args.change.context_after.length,
      this.visibleAfterLength + this.constructor.CONTEXT_STEP
    );
  }

  <template>
    <div class={{this.itemClass}}>
      <div class="suggested-edit-change-item__body">
        {{#if this.hasMoreContextBefore}}
          <div
            class="suggested-edit-change-item__expand suggested-edit-change-item__expand--before"
          >
            <DButton
              @action={{this.expandBefore}}
              @icon="chevron-up"
              @label="discourse_suggested_edits.review.expand_above"
              @disabled={{@disabled}}
              class="btn-flat btn-small suggested-edit-change-item__expand-control"
            />
          </div>
        {{/if}}

        <div class="suggested-edit-change-item__diff">
          {{#if this.showVisibleContextBefore}}
            <pre
              class="suggested-edit-change-item__context suggested-edit-change-item__context--before"
            >…{{this.visibleContextBefore}}</pre>
          {{/if}}
          {{htmlSafe @change.diff_html}}
          {{#if this.showVisibleContextAfter}}
            <pre
              class="suggested-edit-change-item__context suggested-edit-change-item__context--after"
            >{{this.visibleContextAfter}}…</pre>
          {{/if}}
        </div>

        {{#if this.hasMoreContextAfter}}
          <div
            class="suggested-edit-change-item__expand suggested-edit-change-item__expand--after"
          >
            <DButton
              @action={{this.expandAfter}}
              @icon="chevron-down"
              @label="discourse_suggested_edits.review.expand_below"
              @disabled={{@disabled}}
              class="btn-flat btn-small suggested-edit-change-item__expand-control"
            />
          </div>
        {{/if}}
      </div>
      <div class="suggested-edit-change-item__actions">
        <div class="suggested-edit-change-item__actions-right">
          <div class="suggested-edit-change-item__decision-actions">
            <DButton
              @action={{@onAccept}}
              @icon="check"
              @label="discourse_suggested_edits.review.accept"
              @disabled={{@disabled}}
              class="btn-default btn-small suggested-edit-change-item__accept"
            />
            <DButton
              @action={{@onReject}}
              @icon="xmark"
              @label="discourse_suggested_edits.review.reject"
              @disabled={{@disabled}}
              class="btn-default btn-small suggested-edit-change-item__reject"
            />
          </div>
        </div>
      </div>
    </div>
  </template>
}
