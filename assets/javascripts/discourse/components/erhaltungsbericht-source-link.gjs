import Component from "@glimmer/component";
import { htmlSafe } from "@ember/template";
import icon from "discourse/helpers/d-icon";
import { escapeExpression } from "discourse/lib/utilities";
import { i18n } from "discourse-i18n";

/**
 * Displays a link back to the source of an Erhaltungsbericht
 * (either a donation offer or a lottery packet)
 *
 * @component ErhaltungsberichtSourceLink
 * @param {number} args.donationId - ID of source donation
 * @param {Object} args.donationTopic - Donation topic object with url and title
 * @param {string} args.packetUrl - URL to the packet post
 * @param {string} args.packetTitle - Title of the packet
 * @param {string} args.lotteryUrl - URL to the lottery topic
 * @param {string} args.lotteryTitle - Title of the lottery
 */
export default class ErhaltungsberichtSourceLink extends Component {
  /**
   * @returns {boolean}
   */
  get hasDonationSource() {
    return this.args.data?.donationId && this.args.data?.donationTopic;
  }

  /**
   * @returns {boolean}
   */
  get hasPacketSource() {
    return this.args.data?.packetUrl && this.args.data?.lotteryTitle;
  }

  /**
   * Sentence naming the packet and the lottery, each linked to its post
   *
   * @returns {SafeString}
   */
  get packetSourceText() {
    const { packetUrl, packetTitle, lotteryUrl, lotteryTitle } = this.args.data;
    const link = (url, text) =>
      `<a href="${escapeExpression(url)}" class="source-link">${escapeExpression(text)}</a>`;

    return htmlSafe(
      i18n("vzekc_verlosung.erhaltungsbericht.from_lottery_packet", {
        packet: link(packetUrl, packetTitle || lotteryTitle),
        lottery: link(lotteryUrl || packetUrl, lotteryTitle),
      })
    );
  }

  <template>
    {{#if this.hasDonationSource}}
      <div class="erhaltungsbericht-source-link">
        {{icon "gift"}}
        <span class="source-label">{{i18n
            "vzekc_verlosung.erhaltungsbericht.from_donation"
          }}</span>
        <a
          href={{@data.donationTopic.url}}
          class="source-link"
        >{{@data.donationTopic.title}}</a>
      </div>
    {{else if this.hasPacketSource}}
      <div class="erhaltungsbericht-source-link">
        {{icon "dice"}}
        <span class="source-label">{{this.packetSourceText}}</span>
      </div>
    {{/if}}
  </template>
}
