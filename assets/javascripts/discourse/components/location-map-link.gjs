import Component from "@glimmer/component";
import icon from "discourse/helpers/d-icon";
import { i18n } from "discourse-i18n";

/**
 * Displays a location/postcode with dropdown links to map providers
 *
 * @component LocationMapLink
 * @param {string} postcode - The postcode to display and link to maps
 */
export default class LocationMapLink extends Component {
  /**
   * Google Maps search URL
   * @returns {string}
   */
  get googleMapsUrl() {
    return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(this.args.postcode)}`;
  }

  /**
   * OpenStreetMap search URL
   * @returns {string}
   */
  get openStreetMapUrl() {
    return `https://www.openstreetmap.org/search?query=${encodeURIComponent(this.args.postcode)}`;
  }

  /**
   * Apple Maps search URL
   * @returns {string}
   */
  get appleMapsUrl() {
    return `https://maps.apple.com/?q=${encodeURIComponent(this.args.postcode)}`;
  }

  /**
   * Bing Maps search URL
   * @returns {string}
   */
  get bingMapsUrl() {
    return `https://www.bing.com/maps?q=${encodeURIComponent(this.args.postcode)}`;
  }

  <template>
    <div class="location-map-link">
      <a
        href={{this.googleMapsUrl}}
        target="_blank"
        rel="noopener noreferrer"
        class="location-trigger"
      >
        {{icon "location-dot"}}
        <span class="postcode-value">{{@postcode}}</span>
      </a>
      <div class="map-providers-dropdown">
        <div class="dropdown-content">
          <div class="dropdown-arrow"></div>
          <ul class="map-providers-list">
            <li>
              <a
                href={{this.googleMapsUrl}}
                target="_blank"
                rel="noopener noreferrer"
              >
                {{icon "map"}}
                {{i18n "vzekc_verlosung.map_providers.google"}}
              </a>
            </li>
            <li>
              <a
                href={{this.openStreetMapUrl}}
                target="_blank"
                rel="noopener noreferrer"
              >
                {{icon "map"}}
                {{i18n "vzekc_verlosung.map_providers.openstreetmap"}}
              </a>
            </li>
            <li>
              <a
                href={{this.appleMapsUrl}}
                target="_blank"
                rel="noopener noreferrer"
              >
                {{icon "map"}}
                {{i18n "vzekc_verlosung.map_providers.apple"}}
              </a>
            </li>
            <li>
              <a
                href={{this.bingMapsUrl}}
                target="_blank"
                rel="noopener noreferrer"
              >
                {{icon "map"}}
                {{i18n "vzekc_verlosung.map_providers.bing"}}
              </a>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </template>
}
