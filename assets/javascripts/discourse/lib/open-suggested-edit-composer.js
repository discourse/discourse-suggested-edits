import { ajax } from "discourse/lib/ajax";
import {
  fetchSuggestedEdit,
  SUGGEST_EDIT_ACTION,
} from "discourse/plugins/discourse-suggested-edits/discourse/lib/suggested-edits-api";

export async function openSuggestedEditComposer(composer, post) {
  const existingSuggestionId = post.topic?.own_pending_suggested_edit_id;
  const postResult = await ajax(`/posts/${post.id}.json`);
  const originalRaw = postResult.raw;

  const composerOptions = {
    action: SUGGEST_EDIT_ACTION,
    draftKey: `suggestEdit_${post.id}`,
    draftSequence: 0,
    post,
    topic: post.topic,
    reply: originalRaw,
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
  }

  await composer.open(composerOptions);
}
