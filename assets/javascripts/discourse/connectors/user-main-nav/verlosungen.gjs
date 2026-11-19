import Component from "@ember/component";
import { LinkTo } from "@ember/routing";
import { classNames, tagName } from "@ember-decorators/component";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Navigation connector that adds "Verlosungen" tab to user profile
 *
 * @component Verlosungen
 * @param {Object} outletArgs.model - The user model
 */
@tagName("li")
@classNames("user-nav__verlosungen")
export default class Verlosungen extends Component {
  /**
   * Shows the tab only to users who take part in lotteries
   *
   * @param {Object} args - Outlet arguments
   * @param {Object} context - Helper context
   * @param {Object} owner - Application owner
   * @returns {boolean} true if the current user may take part in lotteries
   */
  static shouldRender(args, context, owner) {
    return !!owner.lookup("service:current-user")
      ?.vzekc_verlosung_can_participate;
  }

  <template>
    <LinkTo @route="user.verlosungen" @model={{this.model}}>
      {{icon "gift"}}
      <span>{{i18n "vzekc_verlosung.user_stats.nav_title"}}</span>
    </LinkTo>
  </template>
}
