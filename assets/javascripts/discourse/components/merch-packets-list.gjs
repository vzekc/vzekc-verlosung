import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { next } from "@ember/runloop";
import { service } from "@ember/service";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import { getOwner } from "@ember/owner";
import DButton from "discourse/components/d-button";
import icon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { eq } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";
import MarkMerchShippedModal from "./modal/mark-merch-shipped-modal";

/**
 * List component for displaying merch packets
 *
 * @component MerchPacketsList
 * @param {Array} packets - Array of merch packet objects
 * @param {Function} onPacketShipped - Callback when a packet is marked as shipped
 * @param {string} shipPacketId - Optional packet ID to auto-open shipping modal for
 */
export default class MerchPacketsList extends Component {
  @service modal;
  @service dialog;

  @tracked activeTab = "pending";
  @tracked shippingPacketId = null;
  @tracked lastOpenedShipId = null;

  get pendingPackets() {
    return (this.args.packets || []).filter((p) => p.state === "pending");
  }

  get shippedPackets() {
    return (this.args.packets || []).filter((p) => p.state === "shipped");
  }

  get packetsToShow() {
    return this.activeTab === "pending"
      ? this.pendingPackets
      : this.shippedPackets;
  }

  /**
   * Switch between pending and shipped tabs
   *
   * @param {string} tab - Tab identifier
   */
  @action
  setActiveTab(tab) {
    this.activeTab = tab;
  }

  /**
   * Open the mark as shipped modal
   *
   * @param {Object} packet - The packet to mark as shipped
   * @param {Function} onClose - Optional callback when modal closes
   */
  @action
  openShipModal(packet, onClose) {
    // Update URL to include ship param
    const router = getOwner(this).lookup("service:router");
    router.transitionTo({ queryParams: { ship: packet.id } });

    this.lastOpenedShipId = String(packet.id);

    this.modal.show(MarkMerchShippedModal, {
      model: {
        packet,
        onConfirm: this.confirmShip,
        onClose: () => {
          // Clear ship param when modal closes
          router.transitionTo({ queryParams: { ship: null } });
          onClose?.();
        },
      },
    });
  }

  /**
   * Try to auto-open the modal if shipPacketId is set
   * Called after element is inserted into DOM
   */
  @action
  tryAutoOpenModal() {
    const shipId = this.args.shipPacketId;
    if (!shipId || shipId === this.lastOpenedShipId) {
      return;
    }

    // Defer to next runloop to avoid updating tracked properties during render
    next(() => {
      this._attemptOpenModal(shipId, 0);
    });
  }

  /**
   * Attempt to open modal, with retry if packets not loaded yet
   */
  _attemptOpenModal(shipId, attempt) {
    const packetId = parseInt(shipId, 10);
    const packets = this.args.packets || [];
    const packet = packets.find(
      (p) => p.id === packetId && p.state === "pending"
    );

    if (packet) {
      // openShipModal handles URL param and lastOpenedShipId
      this.openShipModal(packet);
    } else if (attempt < 5 && packets.length === 0) {
      // Retry if packets haven't loaded yet (up to 5 attempts)
      setTimeout(() => this._attemptOpenModal(shipId, attempt + 1), 100);
    } else {
      // Packet not found or not pending, clear the param
      const router = getOwner(this).lookup("service:router");
      router.transitionTo({ queryParams: { ship: null } });
    }
  }

  /**
   * Confirm shipping a packet
   *
   * @param {Object} packet - The packet to ship
   * @param {string} trackingInfo - Optional tracking information
   */
  @action
  async confirmShip(packet, trackingInfo) {
    this.shippingPacketId = packet.id;

    try {
      await ajax(`/vzekc-verlosung/merch-packets/${packet.id}/ship`, {
        type: "PUT",
        data: { tracking_info: trackingInfo },
      });

      this.args.onPacketShipped?.();
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.shippingPacketId = null;
    }
  }

  /**
   * Format a date for display
   *
   * @param {string} dateStr - ISO date string
   * @returns {string} Formatted date
   */
  formatDate(dateStr) {
    if (!dateStr) {
      return "-";
    }
    const date = new Date(dateStr);
    return date.toLocaleDateString("de-DE", {
      day: "2-digit",
      month: "2-digit",
      year: "numeric",
    });
  }

  <template>
    <div class="merch-packets-list" {{didInsert this.tryAutoOpenModal}}>
      <ul class="nav-pills">
        <li>
          <button
            type="button"
            class={{if (eq this.activeTab "pending") "active"}}
            {{on "click" (fn this.setActiveTab "pending")}}
          >
            {{i18n "vzekc_verlosung.merch_packets.tabs.pending"}}
            ({{this.pendingPackets.length}})
          </button>
        </li>
        <li>
          <button
            type="button"
            class={{if (eq this.activeTab "shipped") "active"}}
            {{on "click" (fn this.setActiveTab "shipped")}}
          >
            {{i18n "vzekc_verlosung.merch_packets.tabs.shipped"}}
            ({{this.shippedPackets.length}})
          </button>
        </li>
      </ul>

      {{#if this.packetsToShow.length}}
        <table class="merch-packets-table">
          <thead>
            <tr>
              <th>{{i18n "vzekc_verlosung.merch_packets.table.donation"}}</th>
              <th>{{i18n "vzekc_verlosung.merch_packets.table.donor"}}</th>
              <th>{{i18n "vzekc_verlosung.merch_packets.table.created"}}</th>
              {{#if (eq this.activeTab "shipped")}}
                <th>{{i18n
                    "vzekc_verlosung.merch_packets.table.shipped_at"
                  }}</th>
              {{/if}}
              <th></th>
            </tr>
          </thead>
          <tbody>
            {{#each this.packetsToShow as |packet|}}
              <tr>
                <td class="donation-cell">
                  {{#if packet.donation.url}}
                    <a href={{packet.donation.url}}>
                      {{packet.donation.title}}
                    </a>
                  {{else}}
                    {{packet.donation.title}}
                  {{/if}}
                </td>
                <td class="donor-cell">
                  {{packet.donor_name}}
                  {{#if packet.donor_company}}
                    <br /><small>{{packet.donor_company}}</small>
                  {{/if}}
                </td>
                <td class="date-cell">
                  {{this.formatDate packet.created_at}}
                </td>
                {{#if (eq this.activeTab "shipped")}}
                  <td class="date-cell">
                    {{this.formatDate packet.shipped_at}}
                    {{#if packet.tracking_info}}
                      <div class="tracking-info">
                        {{icon "truck"}}
                        {{packet.tracking_info}}
                      </div>
                    {{/if}}
                  </td>
                {{/if}}
                <td class="actions-cell">
                  {{#if (eq packet.state "pending")}}
                    <DButton
                      @action={{fn this.openShipModal packet}}
                      @icon="truck"
                      @label="vzekc_verlosung.merch_packets.ship"
                      @disabled={{eq this.shippingPacketId packet.id}}
                      class="btn-primary"
                    />
                  {{else}}
                    <span class="shipped-badge">
                      {{icon "check"}}
                      {{i18n "vzekc_verlosung.merch_packets.shipped"}}
                    </span>
                  {{/if}}
                </td>
              </tr>
            {{/each}}
          </tbody>
        </table>
      {{else}}
        <div class="no-packets">
          {{#if (eq this.activeTab "pending")}}
            {{i18n "vzekc_verlosung.merch_packets.no_pending"}}
          {{else}}
            {{i18n "vzekc_verlosung.merch_packets.no_shipped"}}
          {{/if}}
        </div>
      {{/if}}
    </div>
  </template>
}
