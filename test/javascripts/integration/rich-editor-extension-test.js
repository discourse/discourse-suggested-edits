import { settled } from "@ember/test-helpers";
import { module, test } from "qunit";
import {
  registerRichEditorExtension,
  resetRichEditorExtensions,
} from "discourse/lib/composer/rich-editor-extensions";
import { setupRenderingTest } from "discourse/tests/helpers/component-test";
import { setupRichEditor } from "discourse/tests/helpers/rich-editor-helper";
import richEditorExtension from "discourse/plugins/discourse-suggested-edits/discourse/lib/rich-editor-extension";
import { setSuggestEditActive } from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

module(
  "Integration | Component | prosemirror-editor - suggested edits extension",
  function (hooks) {
    setupRenderingTest(hooks);

    hooks.beforeEach(function () {
      this.siteSettings.rich_editor = true;
      setSuggestEditActive(false);

      return resetRichEditorExtensions().then(() => {
        registerRichEditorExtension(richEditorExtension);
      });
    });

    hooks.afterEach(function () {
      setSuggestEditActive(false);
      return resetRichEditorExtensions();
    });

    test("updates highlights on the same edit transaction", async function (assert) {
      const originalRaw = "Original post content here.";

      setSuggestEditActive(true, originalRaw);

      const [{ view }] = await setupRichEditor(assert, originalRaw);
      const endPos = view.state.doc.content.size - 1;

      view.dispatch(view.state.tr.insertText("!", endPos));
      await settled();

      assert
        .dom(".ProseMirror .suggested-edit-changed-block")
        .exists("the block is marked as changed immediately");
      assert
        .dom(".ProseMirror .suggested-edit-changed-text")
        .hasText(
          "!",
          "the newly inserted character is highlighted immediately"
        );
    });
  }
);
