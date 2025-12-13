import Component from "@glimmer/component";
import { action } from "@ember/object";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import { i18n } from "discourse-i18n";

/**
 * Compact controls for lottery list display preferences
 *
 * @component LotteryDisplayModeToggle
 * Includes:
 * - Sort mode toggle (Endet bald/Neueste)
 * - Date display mode toggle (Datum/Countdown)
 */
export default class LotteryDisplayModeToggle extends Component {
  @service lotteryDisplayMode;
  @service currentUser;

  get shouldShow() {
    return !!this.currentUser;
  }

  @action
  setAbsoluteMode() {
    this.lotteryDisplayMode.setMode("absolute");
  }

  @action
  setRelativeMode() {
    this.lotteryDisplayMode.setMode("relative");
  }

  @action
  setSortEndsSoon() {
    this.lotteryDisplayMode.setSortMode("ends_soon");
  }

  @action
  setSortNewest() {
    this.lotteryDisplayMode.setSortMode("newest");
  }

  <template>
    {{#if this.shouldShow}}
      <div class="lottery-list-controls">
        {{! Sort mode toggle }}
        <div class="lottery-control-group sort-mode-toggle">
          <DButton
            @action={{this.setSortEndsSoon}}
            @translatedLabel={{i18n "vzekc_verlosung.list_controls.ends_soon"}}
            class={{if
              this.lotteryDisplayMode.isSortEndsSoon
              "btn-small btn-primary"
              "btn-small btn-default"
            }}
          />
          <DButton
            @action={{this.setSortNewest}}
            @translatedLabel={{i18n "vzekc_verlosung.list_controls.newest"}}
            class={{if
              this.lotteryDisplayMode.isSortNewest
              "btn-small btn-primary"
              "btn-small btn-default"
            }}
          />
        </div>

        {{! Display mode toggle }}
        <div class="lottery-control-group display-mode-toggle">
          <DButton
            @action={{this.setAbsoluteMode}}
            @translatedLabel={{i18n "vzekc_verlosung.display_mode.datum"}}
            class={{if
              this.lotteryDisplayMode.isAbsoluteMode
              "btn-small btn-primary"
              "btn-small btn-default"
            }}
          />
          <DButton
            @action={{this.setRelativeMode}}
            @translatedLabel={{i18n "vzekc_verlosung.display_mode.countdown"}}
            class={{if
              this.lotteryDisplayMode.isRelativeMode
              "btn-small btn-primary"
              "btn-small btn-default"
            }}
          />
        </div>
      </div>
    {{/if}}
  </template>
}
