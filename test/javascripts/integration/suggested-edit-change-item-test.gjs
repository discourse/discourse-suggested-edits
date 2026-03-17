import { tracked } from "@glimmer/tracking";
import { click, fillIn, render } from "@ember/test-helpers";
import { module, test } from "qunit";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import SuggestedEditChangeItem from "discourse/plugins/discourse-suggested-edits/discourse/components/suggested-edit-change-item";

module(
  "Integration | Component | suggested-edit-change-item",
  function (hooks) {
    setupRenderingTest(hooks);

    test("allows expanding surrounding context", async function (assert) {
      const self = new (class {
        longBefore = `${"First hidden sentence before. ".repeat(7)}Second hidden sentence before. Lead paragraph before the change. middle before.`;
        change = {
          diff_html:
            '<div class="inline-diff"><ins class="diff-ins">Updated</ins> <del class="diff-del">Original</del> post content here.</div>',
          preview_context_before: "middle before.",
          preview_context_after: "Trailing paragraph after the change.",
          context_before: this.longBefore,
          context_after:
            "Trailing paragraph after the change. Another trailing sentence after. Final hidden sentence after.",
        };
        status = "pending";
        noop = () => {};
      })();

      await render(
        <template>
          <SuggestedEditChangeItem
            @change={{self.change}}
            @status={{self.status}}
            @onAccept={{self.noop}}
            @onReject={{self.noop}}
            @disabled={{false}}
          />
        </template>
      );

      assert
        .dom(".suggested-edit-change-item__expand--before .d-button-label")
        .hasText("Expand above");
      assert
        .dom(".suggested-edit-change-item__expand--after .d-button-label")
        .hasText("Expand below");
      assert
        .dom(".suggested-edit-change-item__context--before")
        .includesText("middle before.");
      assert
        .dom(".suggested-edit-change-item__context--before")
        .doesNotIncludeText("First hidden sentence before.");

      await click(".suggested-edit-change-item__expand--before button");

      assert
        .dom(".suggested-edit-change-item__context--before")
        .includesText("First hidden sentence before.");
      assert
        .dom(".suggested-edit-change-item__expand--before")
        .exists(
          "the above control stays visible while more hidden context remains"
        );

      await click(".suggested-edit-change-item__expand--before button");

      assert
        .dom(".suggested-edit-change-item__expand--before")
        .doesNotExist(
          "the above control disappears once all prior context is visible"
        );

      assert
        .dom(".suggested-edit-change-item__context--after")
        .doesNotIncludeText("Final hidden sentence after.");

      await click(".suggested-edit-change-item__expand--after button");

      assert
        .dom(".suggested-edit-change-item__context--after")
        .includesText("Final hidden sentence after.");
      assert.dom(".suggested-edit-change-item__expand--after").doesNotExist();
    });

    test("preserves line breaks in inline diffs", async function (assert) {
      const self = new (class {
        change = {
          diff_html:
            '<div class="inline-diff">A: Yes, any post in a topic can be converted to a <del class="diff-del">wiki,</del><ins class="diff-ins">WIKI,</ins> not just the first post.<del class="diff-del">\n\nTo summarise, this is my edit!</del></div>',
          preview_context_before: "",
          preview_context_after: "",
          context_before: "",
          context_after: "",
        };
        status = "pending";
        noop = () => {};
      })();

      await render(
        <template>
          <SuggestedEditChangeItem
            @change={{self.change}}
            @status={{self.status}}
            @onAccept={{self.noop}}
            @onReject={{self.noop}}
            @disabled={{false}}
          />
        </template>
      );

      const inlineDiff = this.element.querySelector(
        ".suggested-edit-change-item__diff .inline-diff"
      );
      assert.notStrictEqual(inlineDiff, null, "inline diff element renders");

      assert.strictEqual(
        window.getComputedStyle(inlineDiff).whiteSpace,
        "pre-wrap",
        "inline diffs preserve newline rendering"
      );
      assert.true(
        inlineDiff.textContent.includes(
          "post.\n\nTo summarise, this is my edit!"
        ),
        "diff text includes newline boundaries"
      );
    });

    test("edit button opens textarea and save commits the edit", async function (assert) {
      let savedText = null;

      const self = new (class {
        @tracked isEditing = false;
        @tracked isAnyEditing = false;
        change = {
          id: 1,
          after_text: "Original after",
          diff_html: '<div class="inline-diff">Original after</div>',
          preview_context_before: "",
          preview_context_after: "",
          context_before: "",
          context_after: "",
        };
        status = "pending";

        noop = () => {};
        onEdit = () => {
          this.isEditing = true;
          this.isAnyEditing = true;
        };
        onSaveEdit = (text) => (savedText = text);
        onCancelEdit = () => {};
      })();

      await render(
        <template>
          <SuggestedEditChangeItem
            @change={{self.change}}
            @status={{self.status}}
            @onAccept={{self.noop}}
            @onReject={{self.noop}}
            @onEdit={{self.onEdit}}
            @onSaveEdit={{self.onSaveEdit}}
            @onCancelEdit={{self.onCancelEdit}}
            @isEditing={{self.isEditing}}
            @isAnyEditing={{self.isAnyEditing}}
            @disabled={{false}}
          />
        </template>
      );

      assert
        .dom(".suggested-edit-change-item__edit")
        .exists("edit button is rendered");
      assert
        .dom(".suggested-edit-change-item__editor")
        .doesNotExist("editor is not shown initially");

      await click(".suggested-edit-change-item__edit");

      assert
        .dom(".suggested-edit-change-item__editor")
        .exists("editor is shown after clicking edit");
      assert
        .dom(".suggested-edit-change-item__editor-textarea")
        .hasValue("Original after");

      await fillIn(
        ".suggested-edit-change-item__editor-textarea",
        "Custom text"
      );
      await click(".suggested-edit-change-item__save-edit");

      assert.strictEqual(
        savedText,
        "Custom text",
        "onSaveEdit receives the edited text"
      );
    });

    test("cancel edit invokes onCancelEdit without saving", async function (assert) {
      let cancelCalled = false;
      let savedText = null;

      const self = new (class {
        change = {
          id: 1,
          after_text: "Original after",
          diff_html: '<div class="inline-diff">Original after</div>',
          preview_context_before: "",
          preview_context_after: "",
          context_before: "",
          context_after: "",
        };
        status = "pending";
        noop = () => {};
        onSaveEdit = (text) => (savedText = text);
        onCancelEdit = () => (cancelCalled = true);
      })();

      await render(
        <template>
          <SuggestedEditChangeItem
            @change={{self.change}}
            @status={{self.status}}
            @onAccept={{self.noop}}
            @onReject={{self.noop}}
            @onEdit={{self.noop}}
            @onSaveEdit={{self.onSaveEdit}}
            @onCancelEdit={{self.onCancelEdit}}
            @isEditing={{true}}
            @isAnyEditing={{true}}
            @disabled={{false}}
          />
        </template>
      );

      await fillIn(
        ".suggested-edit-change-item__editor-textarea",
        "Unsaved draft"
      );
      await click(".suggested-edit-change-item__cancel-edit");

      assert.true(cancelCalled, "onCancelEdit was called");
      assert.strictEqual(savedText, null, "onSaveEdit was not called");
    });

    test("shows edited badge when editedAfterText is provided", async function (assert) {
      const self = new (class {
        change = {
          id: 1,
          after_text: "Original after",
          diff_html: '<div class="inline-diff">Original after</div>',
          preview_context_before: "",
          preview_context_after: "",
          context_before: "",
          context_after: "",
        };
        status = "accepted";
        noop = () => {};
      })();

      await render(
        <template>
          <SuggestedEditChangeItem
            @change={{self.change}}
            @status={{self.status}}
            @onAccept={{self.noop}}
            @onReject={{self.noop}}
            @onEdit={{self.noop}}
            @onSaveEdit={{self.noop}}
            @onCancelEdit={{self.noop}}
            @isEditing={{false}}
            @isAnyEditing={{false}}
            @editedAfterText="Custom reviewer text"
            @disabled={{false}}
          />
        </template>
      );

      assert
        .dom(".suggested-edit-change-item__edited-badge")
        .exists("edited badge is shown");
      assert
        .dom(".suggested-edit-change-item__edited-text")
        .hasText("Custom reviewer text");
      assert
        .dom(".suggested-edit-change-item__diff .inline-diff")
        .doesNotExist("original diff is not shown");
    });

    test("edit button is disabled when another hunk is being edited", async function (assert) {
      const self = new (class {
        change = {
          id: 1,
          after_text: "Original after",
          diff_html: '<div class="inline-diff">Original after</div>',
          preview_context_before: "",
          preview_context_after: "",
          context_before: "",
          context_after: "",
        };
        status = "pending";
        noop = () => {};
      })();

      await render(
        <template>
          <SuggestedEditChangeItem
            @change={{self.change}}
            @status={{self.status}}
            @onAccept={{self.noop}}
            @onReject={{self.noop}}
            @onEdit={{self.noop}}
            @onSaveEdit={{self.noop}}
            @onCancelEdit={{self.noop}}
            @isEditing={{false}}
            @isAnyEditing={{true}}
            @disabled={{false}}
          />
        </template>
      );

      assert
        .dom(".suggested-edit-change-item__edit")
        .isDisabled("edit button is disabled when another hunk is editing");
    });
  }
);
