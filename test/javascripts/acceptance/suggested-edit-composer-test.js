import { visit } from "@ember/test-helpers";
import { test } from "qunit";
import sinon from "sinon";
import Composer from "discourse/models/composer";
import { acceptance } from "discourse/tests/helpers/qunit-helpers";
import { SUGGEST_EDIT_ACTION } from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

function buildComposerModel(owner, properties = {}) {
  const store = owner.lookup("service:store");
  const model = store.createRecord("composer");

  model.setProperties({
    action: Composer.REPLY,
    composeState: Composer.OPEN,
    draftKey: "topic_280",
    draftSequence: 0,
    reply: "Revised post content",
    originalText: "",
    ...properties,
  });

  return model;
}

acceptance("Discourse Suggested Edits - Composer", function (needs) {
  needs.user();
  needs.settings({ suggested_edits_enabled: true });

  test("suggested edit mode never saves drafts", async function (assert) {
    await visit("/");

    const composerService = this.owner.lookup("service:composer");
    const model = buildComposerModel(this.owner, {
      action: SUGGEST_EDIT_ACTION,
      draftKey: "suggestEdit_1",
      originalText: "Original post content",
    });

    composerService.set("model", model);

    const saveDraftStub = sinon.stub(model, "saveDraft").resolves();

    await composerService._saveDraft();

    assert.false(
      saveDraftStub.called,
      "suggested edit composers skip draft persistence entirely"
    );
  });

  test("other composer modes still save drafts", async function (assert) {
    await visit("/");

    const composerService = this.owner.lookup("service:composer");
    const model = buildComposerModel(this.owner);

    composerService.set("model", model);

    const saveDraftStub = sinon.stub(model, "saveDraft").resolves();

    await composerService._saveDraft();

    assert.true(
      saveDraftStub.calledOnce,
      "regular composers continue to use the normal draft flow"
    );
  });
});
