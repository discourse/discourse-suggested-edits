import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";

const SuggestedEditsStaleWarning = <template>
  <div class="suggested-edits-stale-warning alert alert-warning">
    <span>{{i18n "discourse_suggested_edits.review.stale_warning"}}</span>
    <DButton
      @action={{@onDismiss}}
      @label="discourse_suggested_edits.review.dismiss"
      class="btn-flat btn-small"
    />
  </div>
</template>;

export default SuggestedEditsStaleWarning;
