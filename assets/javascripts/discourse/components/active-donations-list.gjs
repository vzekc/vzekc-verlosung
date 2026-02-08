import avatar from "discourse/helpers/avatar";
import icon from "discourse/helpers/d-icon";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import LocationMapLink from "./location-map-link";

/**
 * Builds CSS class for username based on user roles
 *
 * @param {Object} facilitator - Facilitator object with admin/moderator flags
 * @returns {string} CSS class string
 */
function usernameClass(facilitator) {
  const classes = ["username"];
  if (facilitator.admin || facilitator.moderator) {
    classes.push("staff");
  }
  if (facilitator.admin) {
    classes.push("admin");
  }
  if (facilitator.moderator) {
    classes.push("moderator");
  }
  return classes.join(" ");
}

/**
 * Builds CSS class for user title based on primary group
 *
 * @param {Object} facilitator - Facilitator object with primary_group_name
 * @returns {string} CSS class string
 */
function titleClass(facilitator) {
  if (facilitator.primary_group_name) {
    return `user-title user-title--${facilitator.primary_group_name.toLowerCase()}`;
  }
  return "user-title";
}

/**
 * Formats a date as a relative time ago string in German
 *
 * @param {string|Date} date - Date to format
 * @returns {string} Formatted relative time string
 */
function formatTimeAgo(date) {
  if (!date) {
    return "";
  }
  const d = new Date(date);
  const now = new Date();
  const diffMs = now - d;
  const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));
  const diffHours = Math.floor(diffMs / (1000 * 60 * 60));
  const diffMinutes = Math.floor(diffMs / (1000 * 60));

  if (diffDays > 0) {
    return diffDays === 1 ? "vor 1 Tag" : `vor ${diffDays} Tagen`;
  } else if (diffHours > 0) {
    return diffHours === 1 ? "vor 1 Stunde" : `vor ${diffHours} Stunden`;
  } else if (diffMinutes > 0) {
    return diffMinutes === 1 ? "vor 1 Minute" : `vor ${diffMinutes} Minuten`;
  }
  return "gerade eben";
}

/**
 * Gets CSS class for donation status
 *
 * @param {string} state - Donation state
 * @returns {string} CSS class string
 */
function stateClass(state) {
  return `donation-state donation-state--${state}`;
}

/**
 * Displays a list of active donations
 *
 * @component ActiveDonationsList
 * @param {Array} donations - Array of donation objects
 */
<template>
  {{#if @donations.length}}
    <div class="active-donations-list">
      {{#each @donations as |donation|}}
        <div
          class="active-donation-card
            {{if donation.assigned_picker 'has-picker'}}
            {{if donation.unread 'is-unread'}}"
        >
          <div class="active-donation-header">
            <h3 class="active-donation-title">
              <a href={{donation.url}}>{{donation.title}}</a>
            </h3>
            <div class="active-donation-meta">
              <div class="names trigger-user-card">
                {{avatar donation.facilitator imageSize="tiny"}}
                <span class={{usernameClass donation.facilitator}}>
                  <a
                    href="/u/{{donation.facilitator.username}}"
                    data-user-card={{donation.facilitator.username}}
                  >
                    {{donation.facilitator.username}}
                    {{#if donation.facilitator.moderator}}
                      <span
                        class="svg-icon-title"
                        title={{i18n "user.moderator_tooltip"}}
                      >
                        {{icon "shield-halved"}}
                      </span>
                    {{/if}}
                  </a>
                </span>
                {{#if donation.facilitator.title}}
                  <span class={{titleClass donation.facilitator}}>
                    {{donation.facilitator.title}}
                  </span>
                {{/if}}
              </div>
            </div>
          </div>

          <div class="active-donation-info">
            <div class="active-donation-details">
              <div class="donation-detail donation-age">
                {{icon "clock"}}
                <span class="detail-value">{{formatTimeAgo
                    donation.published_at
                  }}</span>
              </div>
              {{#if donation.postcode}}
                <div class="donation-detail donation-location">
                  <LocationMapLink @postcode={{donation.postcode}} />
                </div>
              {{/if}}
            </div>

            <div class="active-donation-status">
              <div class="donation-detail donation-offers">
                {{icon "hand-paper"}}
                <span class="detail-value">{{donation.pickup_offer_count}}
                  {{i18n
                    "vzekc_verlosung.active_donations.offers"
                    count=donation.pickup_offer_count
                  }}</span>
              </div>

              <div class={{stateClass donation.state}}>
                {{#if (eq donation.state "open")}}
                  {{icon "circle"}}
                  <span>{{i18n "vzekc_verlosung.donation.state.open"}}</span>
                {{else if (eq donation.state "assigned")}}
                  {{icon "user-check"}}
                  <span>{{i18n
                      "vzekc_verlosung.donation.state.assigned"
                    }}</span>
                {{else if (eq donation.state "picked_up")}}
                  {{icon "circle-check"}}
                  <span>{{i18n
                      "vzekc_verlosung.donation.state.picked_up"
                    }}</span>
                {{else if (eq donation.state "closed")}}
                  {{icon "circle-check"}}
                  <span>{{i18n "vzekc_verlosung.donation.state.closed"}}</span>
                {{/if}}
              </div>
            </div>

            {{#if donation.assigned_picker}}
              <div class="active-donation-picker">
                <div class="picker-info">
                  {{icon "truck"}}
                  <span class="picker-label">{{i18n
                      "vzekc_verlosung.active_donations.picker"
                    }}:</span>
                  {{avatar donation.assigned_picker imageSize="tiny"}}
                  <a
                    href="/u/{{donation.assigned_picker.username}}"
                    class="picker-username"
                    data-user-card={{donation.assigned_picker.username}}
                  >
                    {{donation.assigned_picker.username}}
                  </a>
                </div>
              </div>
            {{/if}}

            {{#if donation.has_lottery}}
              <div class="active-donation-outcome">
                {{icon "dice"}}
                <span>{{i18n
                    "vzekc_verlosung.active_donations.lottery_created"
                  }}</span>
              </div>
            {{else if donation.has_erhaltungsbericht}}
              <div class="active-donation-outcome">
                {{icon "file-lines"}}
                <span>{{i18n
                    "vzekc_verlosung.active_donations.erhaltungsbericht_created"
                  }}</span>
              </div>
            {{/if}}
          </div>
        </div>
      {{/each}}
    </div>
  {{else}}
    <div class="no-active-donations">
      {{i18n "vzekc_verlosung.active_donations.no_donations"}}
    </div>
  {{/if}}
</template>
