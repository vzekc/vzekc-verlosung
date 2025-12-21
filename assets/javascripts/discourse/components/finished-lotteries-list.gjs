import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Formats a date as a short date string
 *
 * @param {string|Date} date - Date to format
 * @returns {string} Formatted date string
 */
function formatShortDate(date) {
  if (!date) {
    return "";
  }
  const d = new Date(date);
  return d.toLocaleDateString("de-DE", {
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

/**
 * Displays a list of finished lotteries
 *
 * @component FinishedLotteriesList
 * @param {Array} lotteries - Array of finished lottery objects
 */
<template>
  {{#if @lotteries.length}}
    <div class="finished-lotteries-list">
      {{#each @lotteries as |lottery|}}
        <div class="finished-lottery-card">
          <div class="finished-lottery-header">
            <h3 class="finished-lottery-title">
              <a href={{lottery.url}}>{{lottery.title}}</a>
            </h3>
            <div class="finished-lottery-meta">
              <div class="names trigger-user-card">
                {{avatar lottery.creator imageSize="tiny"}}
                <a
                  href="/u/{{lottery.creator.username}}"
                  data-user-card={{lottery.creator.username}}
                  class="username"
                >
                  {{lottery.creator.username}}
                </a>
              </div>
            </div>
          </div>

          <div class="finished-lottery-info">
            <div class="finished-lottery-dates">
              <div class="lottery-date">
                {{icon "calendar-check"}}
                <span class="date-value">{{formatShortDate
                    lottery.drawn_at
                  }}</span>
              </div>
            </div>

            <div class="finished-lottery-stats">
              <div class="stat-item">
                {{icon "cube"}}
                <span>{{lottery.packet_count}}
                  {{i18n "vzekc_verlosung.active.packets"}}</span>
              </div>
              <div class="stat-item">
                {{icon "users"}}
                <span>{{lottery.participant_count}}
                  {{i18n "vzekc_verlosung.active.participants"}}</span>
              </div>
            </div>
          </div>
        </div>
      {{/each}}
    </div>
  {{else}}
    <div class="no-finished-lotteries">
      {{i18n "vzekc_verlosung.active.no_finished_lotteries"}}
    </div>
  {{/if}}
</template>
