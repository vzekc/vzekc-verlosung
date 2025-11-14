import Component from "@glimmer/component";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Displays a link back to the source of an Erhaltungsbericht
 * (either a donation offer or a lottery packet)
 *
 * @component ErhaltungsberichtSourceLink
 * @param {number} args.donationId - ID of source donation
 * @param {Object} args.donationTopic - Donation topic object with url and title
 * @param {string} args.packetUrl - URL to the packet post
 * @param {string} args.lotteryTitle - Title of the lottery
 */
export default class ErhaltungsberichtSourceLink extends Component {
  get hasDonationSource() {
    return this.args.data?.donationId && this.args.data?.donationTopic;
  }

  get hasPacketSource() {
    return this.args.data?.packetUrl && this.args.data?.lotteryTitle;
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
        <span class="source-label">{{i18n
            "vzekc_verlosung.erhaltungsbericht.from_lottery"
          }}</span>
        <a
          href={{@data.packetUrl}}
          class="source-link"
        >{{@data.lotteryTitle}}</a>
      </div>
    {{/if}}
  </template>
}
