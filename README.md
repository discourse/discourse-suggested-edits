# discourse-suggested-edits

Allows community members to suggest edits to first posts in configured categories or tags. Designated reviewers can accept, reject, or cherry-pick individual changes before applying them to the post.

## How it works

**Suggesting an edit** — Members of the configured suggest group see a "Suggest Edit" button on eligible first posts. Clicking it opens the composer pre-filled with the original post content. After making changes (and optionally providing a reason), the user submits the suggestion. The plugin extracts individual change hunks automatically.

**Reviewing suggestions** — Reviewers (members of the review group, or the post author) see a banner and badge indicating pending suggestions. Opening the review modal shows each suggestion with inline diffs. Reviewers can accept or reject changes individually, then apply the accepted set or dismiss the suggestion entirely.

**Revising / withdrawing** — A suggestion author can revise their pending suggestion or withdraw it before a reviewer acts on it.

**Staleness** — If the post is edited after a suggestion is created, the suggestion is marked stale and cannot be applied.

## Configuration

Enable the plugin and configure it under Admin > Settings:

| Setting | Description | Default |
|---|---|---|
| `suggested_edits_enabled` | Master toggle | `false` |
| `suggested_edits_suggest_groups` | Groups whose members can suggest edits | — |
| `suggested_edits_review_groups` | Groups whose members can review/apply edits (post authors can always review) | — |
| `suggested_edits_included_categories` | Categories where suggesting is available | — |
| `suggested_edits_included_tags` | Tags where suggesting is available (OR with categories) | — |
| `suggested_edits_max_creates_per_minute` | Rate limit for creating suggestions | `5` |
| `suggested_edits_max_revisions_per_minute` | Rate limit for revising suggestions | `10` |

## Constraints

- Only first posts are eligible for suggestions.
- A user can have at most one pending suggestion per post.
- The suggested text must differ from the original and respect the `min_first_post_length` site setting.
