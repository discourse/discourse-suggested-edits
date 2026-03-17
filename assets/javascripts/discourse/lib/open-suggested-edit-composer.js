import { ajax } from "discourse/lib/ajax";
import {
  fetchSuggestedEdit,
  SUGGEST_EDIT_ACTION,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

function buildSuggestedEditDraftKey(postId) {
  // Suggested edits never persist drafts, so use a one-shot key per session.
  return `suggestEdit_${postId}_${Date.now()}`;
}

export async function openSuggestedEditComposer(composer, post) {
  const existingSuggestionId = post.topic?.own_pending_suggested_edit_id;
  const postResult = await ajax(`/posts/${post.id}.json`);
  const originalRaw = postResult.raw;

  const composerOptions = {
    action: SUGGEST_EDIT_ACTION,
    draftKey: buildSuggestedEditDraftKey(post.id),
    draftSequence: 0,
    post,
    topic: post.topic,
    reply: originalRaw,
    warningsDisabled: true,
    metaData: {
      postId: post.id,
      originalRaw,
    },
  };

  if (existingSuggestionId) {
    const result = await fetchSuggestedEdit(existingSuggestionId);
    const suggestion = result.suggested_edit;

    composerOptions.reply = suggestion.raw_suggestion;
    composerOptions.metaData.existingSuggestionId = suggestion.id;
    composerOptions.metaData.reason = suggestion.reason;
  }

  await composer.open(composerOptions);
}
