import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { htmlSafe } from "@ember/template";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";

/**
 * Statistics component showing merch packets shipped per month
 *
 * @component MerchPacketsStats
 */
export default class MerchPacketsStats extends Component {
  @tracked stats = null;
  @tracked loading = true;

  get totalCount() {
    if (!this.stats) {
      return 0;
    }
    return this.stats.reduce((sum, s) => sum + s.count, 0);
  }

  @action
  async loadStats() {
    let result;
    try {
      result = await ajax("/vzekc-verlosung/merch-packets/stats.json");
    } catch (error) {
      popupAjaxError(error);
      this.loading = false;
      return;
    }

    const rows = result.stats || [];
    const maxCount = Math.max(1, ...rows.map((s) => s.count));
    const locale = document.documentElement.lang || undefined;

    this.stats = rows.map((entry) => {
      const [year, month] = entry.month.split("-");
      const date = new Date(parseInt(year, 10), parseInt(month, 10) - 1, 1);
      const pct = (entry.count / maxCount) * 100;

      return {
        label: date.toLocaleDateString(locale, {
          month: "long",
          year: "numeric",
        }),
        count: entry.count,
        barStyle: htmlSafe(`width: ${pct}%`),
      };
    });
    this.loading = false;
  }

  <template>
    <div class="merch-packets-stats" {{didInsert this.loadStats}}>
      {{#if this.loading}}
        <div class="loading-container">
          <div class="spinner small"></div>
        </div>
      {{else if this.stats.length}}
        <div class="stats-total">
          {{this.totalCount}}
          {{i18n "vzekc_verlosung.merch_packets.stats.total_shipped"}}
        </div>
        <div class="stats-chart">
          {{#each this.stats as |entry|}}
            <div class="stats-row">
              <span class="stats-month">{{entry.label}}</span>
              <div class="stats-bar-container">
                <div class="stats-bar" style={{entry.barStyle}}>
                  <span class="stats-count">{{entry.count}}</span>
                </div>
              </div>
            </div>
          {{/each}}
        </div>
      {{else}}
        <div class="no-packets">
          {{i18n "vzekc_verlosung.merch_packets.stats.no_data"}}
        </div>
      {{/if}}
    </div>
  </template>
}
