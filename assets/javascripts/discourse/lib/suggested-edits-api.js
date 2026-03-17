import { ajax } from "discourse/lib/ajax";

export const SUGGEST_EDIT_ACTION = "suggestEdit";

let _suggestEditActive = false;
let _originalRaw = null;

export function setSuggestEditActive(active, originalRaw = null) {
  _suggestEditActive = active;
  _originalRaw = active ? originalRaw : null;
}

export function isSuggestEditActive() {
  return _suggestEditActive;
}

export function getOriginalRaw() {
  return _originalRaw;
}

const BASE = "/suggested-edits/suggestions";

export function createSuggestedEdit({ postId, raw, reason }) {
  return ajax(BASE, {
    type: "POST",
    data: { post_id: postId, raw, reason },
  });
}

export function updateSuggestedEdit(id, { raw, reason }) {
  return ajax(`${BASE}/${id}`, {
    type: "PUT",
    data: { raw, reason },
  });
}

export function deleteSuggestedEdit(id) {
  return ajax(`${BASE}/${id}`, {
    type: "DELETE",
  });
}

export function fetchSuggestedEdits(postId) {
  return ajax(BASE, {
    data: { post_id: postId },
  });
}

export function fetchSuggestedEdit(id) {
  return ajax(`${BASE}/${id}`);
}

export function applySuggestedEdit(
  id,
  acceptedChangeIds,
  changeOverrides = {}
) {
  const data = { accepted_change_ids: acceptedChangeIds };
  if (Object.keys(changeOverrides).length > 0) {
    data.change_overrides = changeOverrides;
  }
  return ajax(`${BASE}/${id}/apply`, {
    type: "PUT",
    data,
  });
}

export function dismissSuggestedEdit(id) {
  return ajax(`${BASE}/${id}/dismiss`, {
    type: "PUT",
  });
}
