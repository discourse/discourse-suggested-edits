import { click, render } from "@ember/test-helpers";
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
  }
);
