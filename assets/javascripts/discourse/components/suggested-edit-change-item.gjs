import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { htmlSafe } from "@ember/template";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";

export default class SuggestedEditChangeItem extends Component {
  static CONTEXT_STEP = 220;

  @tracked visibleBeforeLength = 0;
  @tracked visibleAfterLength = 0;
  @tracked editText = "";

  constructor() {
    super(...arguments);
    this.visibleBeforeLength =
      this.args.change.preview_context_before?.length || 0;
    this.visibleAfterLength =
      this.args.change.preview_context_after?.length || 0;
  }

  get isSideBySide() {
    return this.args.viewMode === "side-by-side";
  }

  get isAccepted() {
    return this.args.status === "accepted";
  }

  get isRejected() {
    return this.args.status === "rejected";
  }

  get isEdited() {
    return this.args.editedAfterText !== undefined;
  }

  get editDisabled() {
    return this.args.disabled || this.args.isAnyEditing;
  }

  get itemClass() {
    let cls = "suggested-edit-change-item";
    if (this.isAccepted) {
      cls += " suggested-edit-change-item--accepted";
    } else if (this.isRejected) {
      cls += " suggested-edit-change-item--rejected";
    } else {
      cls += " suggested-edit-change-item--pending";
    }
    if (this.args.isEditing) {
      cls += " suggested-edit-change-item--editing";
    }
    return cls;
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

  @action
  startEdit() {
    this.editText =
      this.args.editedAfterText ?? this.args.change.after_text ?? "";
    this.args.onEdit?.();
  }

  @action
  handleEditInput(event) {
    this.editText = event.target.value;
  }

  @action
  saveEdit() {
    this.args.onSaveEdit?.(this.editText);
  }

  @action
  cancelEdit() {
    this.args.onCancelEdit?.();
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

        {{#if @isEditing}}
          <div class="suggested-edit-change-item__editor">
            <textarea
              class="suggested-edit-change-item__editor-textarea"
              {{on "input" this.handleEditInput}}
            >{{this.editText}}</textarea>
            <div class="suggested-edit-change-item__editor-actions">
              <DButton
                @action={{this.saveEdit}}
                @icon="check"
                @label="discourse_suggested_edits.review.save_edit"
                class="btn-primary btn-small suggested-edit-change-item__save-edit"
              />
              <DButton
                @action={{this.cancelEdit}}
                @label="discourse_suggested_edits.review.cancel_edit"
                class="btn-default btn-small suggested-edit-change-item__cancel-edit"
              />
            </div>
          </div>
        {{else if this.isEdited}}
          <div class="suggested-edit-change-item__diff">
            <span class="suggested-edit-change-item__edited-badge">
              {{i18n "discourse_suggested_edits.review.edited"}}
            </span>
            <pre
              class="suggested-edit-change-item__edited-text"
            >{{@editedAfterText}}</pre>
          </div>
        {{else if this.isSideBySide}}
          <div
            class="suggested-edit-change-item__diff suggested-edit-change-item__diff--side-by-side"
          >
            <div class="suggested-edit-change-item__side">
              {{#if this.showVisibleContextBefore}}
                <pre
                  class="suggested-edit-change-item__context suggested-edit-change-item__context--before"
                >…{{this.visibleContextBefore}}</pre>
              {{/if}}
              {{htmlSafe @change.side_by_side_before_html}}
              {{#if this.showVisibleContextAfter}}
                <pre
                  class="suggested-edit-change-item__context suggested-edit-change-item__context--after"
                >{{this.visibleContextAfter}}…</pre>
              {{/if}}
            </div>
            <div class="suggested-edit-change-item__side">
              {{#if this.showVisibleContextBefore}}
                <pre
                  class="suggested-edit-change-item__context suggested-edit-change-item__context--before"
                >…{{this.visibleContextBefore}}</pre>
              {{/if}}
              {{htmlSafe @change.side_by_side_after_html}}
              {{#if this.showVisibleContextAfter}}
                <pre
                  class="suggested-edit-change-item__context suggested-edit-change-item__context--after"
                >{{this.visibleContextAfter}}…</pre>
              {{/if}}
            </div>
          </div>
        {{else}}
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
        {{/if}}

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
              @action={{this.startEdit}}
              @icon="pencil"
              @label="discourse_suggested_edits.review.edit"
              @disabled={{this.editDisabled}}
              class="btn-default btn-small suggested-edit-change-item__edit"
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
