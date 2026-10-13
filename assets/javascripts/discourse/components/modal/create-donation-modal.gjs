import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
import { cancel, next } from "@ember/runloop";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { longDate } from "discourse/lib/formatter";
import Composer from "discourse/models/composer";
import autoFocus from "discourse/modifiers/auto-focus";
import { not } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Modal component for creating a new donation offer
 *
 * @component CreateDonationModal
 * Two-step process: collect title and postcode, then open composer.
 * The form can be pre-filled from the donor's email thread (.eml files);
 * the imported messages are then shown below the form for review.
 */
export default class CreateDonationModal extends Component {
  @service composer;
  @service siteSettings;

  @tracked title = "";
  @tracked postcode = "";
  @tracked isSubmitting = false;

  @tracked skipMerchPacket = false;
  @tracked donorName = "";
  @tracked donorCompany = "";
  @tracked donorStreet = "";
  @tracked donorStreetNumber = "";
  @tracked donorPostcode = "";
  @tracked donorCity = "";
  @tracked donorEmail = "";
  @tracked isImporting = false;
  @tracked isDraggingFiles = false;
  @tracked importedRaw = null;
  @tracked importedMessages = [];
  @tracked skippedImages = [];

  /**
   * Run-loop timer of the deferred handoff import
   *
   * @type {Object}
   */
  handoffTimer = null;

  constructor() {
    super(...arguments);

    // The import updates tracked state, so it starts after this render.
    const token = this.args.model?.handoffToken;
    if (token) {
      this.handoffTimer = next(this, this.importHandoff, token);
    }
  }

  willDestroy() {
    super.willDestroy(...arguments);
    cancel(this.handoffTimer);
  }

  /**
   * Check if user can submit
   *
   * @type {boolean}
   */
  get canSubmit() {
    const basicValid =
      this.title.trim().length >= 3 && this.postcode.trim().length >= 3;

    if (!basicValid) {
      return false;
    }

    // If merch packet is NOT skipped, require address fields and email
    if (!this.skipMerchPacket) {
      return (
        this.donorName.trim().length >= 2 &&
        this.donorStreet.trim().length >= 2 &&
        this.donorStreetNumber.trim().length >= 1 &&
        this.donorPostcode.trim().length >= 4 &&
        this.donorCity.trim().length >= 2 &&
        this.donorEmailValid
      );
    }

    return true;
  }

  /**
   * Whether the donor email looks like an address (local part, @, domain)
   *
   * @type {boolean}
   */
  get donorEmailValid() {
    return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(this.donorEmail.trim());
  }

  /**
   * Updates field value
   *
   * @param {string} field - Field name
   * @param {Event} event - Input event
   */
  @action
  updateField(field, event) {
    this[field] = event.target.value;
  }

  /**
   * Toggle skip merch packet checkbox
   */
  @action
  toggleSkipMerchPacket() {
    this.skipMerchPacket = !this.skipMerchPacket;
  }

  /**
   * Comma-separated names of the photos that could not be uploaded
   *
   * @type {string}
   */
  get skippedImageNames() {
    return this.skippedImages.join(", ");
  }

  /**
   * Imports the .eml files picked in the file input
   *
   * @param {Event} event - Change event of the file input
   */
  @action
  async importSelectedFiles(event) {
    const files = [...event.target.files];
    event.target.value = "";
    await this.importEmails(files);
  }

  /**
   * Marks the drop zone while files are dragged over it
   *
   * @param {DragEvent} event - Drag event
   */
  @action
  dragOver(event) {
    event.preventDefault();
    this.isDraggingFiles = true;
  }

  /**
   * Removes the drop zone marker
   */
  @action
  dragLeave() {
    this.isDraggingFiles = false;
  }

  /**
   * Imports the .eml files dropped on the drop zone
   *
   * @param {DragEvent} event - Drop event
   */
  @action
  async dropFiles(event) {
    event.preventDefault();
    this.isDraggingFiles = false;
    await this.importEmails([...event.dataTransfer.files]);
  }

  /**
   * Sends the messages of the donor's email thread to the server and fills
   * the form with the extracted offer
   *
   * @param {File[]} files - The thread's messages as .eml files or zips of them
   */
  @action
  async importEmails(files) {
    if (files.length === 0) {
      return;
    }

    const formData = new FormData();
    files.forEach((file) => formData.append("files[]", file));
    await this.requestImport({
      data: formData,
      processData: false,
      contentType: false,
    });
  }

  /**
   * Fills the form from an email thread handed over by Herold
   *
   * @param {string} token - One-time handoff token
   */
  async importHandoff(token) {
    await this.requestImport({ data: { handoff_token: token } });
  }

  /**
   * Posts to the import endpoint and applies the result
   *
   * @param {Object} options - ajax options carrying the request data
   */
  async requestImport(options) {
    if (this.isImporting) {
      return;
    }

    this.isImporting = true;
    try {
      const result = await ajax("/vzekc-verlosung/donations/import-email", {
        type: "POST",
        ...options,
      });
      this.applyImport(result);
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isImporting = false;
    }
  }

  /**
   * Fills the form from an import result, keeping fields the import found
   * no value for
   *
   * @param {Object} result - Response of the import endpoint
   */
  applyImport(result) {
    const donor = result.donor;
    const values = {
      title: result.title,
      postcode: result.pickup_location,
      donorName: donor.name,
      donorCompany: donor.company,
      donorStreet: donor.street,
      donorStreetNumber: donor.street_number,
      donorPostcode: donor.postcode,
      donorCity: donor.city,
      donorEmail: donor.email,
    };
    Object.entries(values).forEach(([field, value]) => {
      if (value) {
        this[field] = value;
      }
    });
    this.skipMerchPacket = false;
    this.importedRaw = result.raw;
    this.skippedImages = result.skipped_images;
    this.importedMessages = result.messages.map((message) => ({
      ...message,
      displayDate: message.date ? longDate(new Date(message.date)) : "",
    }));
  }

  /**
   * Prevent Enter key from submitting forms
   *
   * @param {KeyboardEvent} event - Keyboard event
   */
  @action
  handleKeyDown(event) {
    if (event.key === "Enter") {
      event.preventDefault();
      event.stopPropagation();
      return false;
    }
  }

  /**
   * Prevent form submission
   *
   * @param {Event} event - Submit event
   */
  @action
  preventSubmit(event) {
    event.preventDefault();
    return false;
  }

  /**
   * Get the submit button label key
   *
   * @type {string}
   */
  get submitLabelKey() {
    return this.isSubmitting
      ? "vzekc_verlosung.donation_modal.creating"
      : "vzekc_verlosung.donation_modal.create";
  }

  /**
   * Get the submit button icon
   *
   * @type {string}
   */
  get submitIcon() {
    return this.isSubmitting ? "spinner" : null;
  }

  /**
   * Submit the donation creation and open composer
   */
  @action
  async submit() {
    if (this.isSubmitting || !this.canSubmit) {
      return;
    }

    this.isSubmitting = true;

    try {
      const requestData = {
        postcode: this.postcode.trim(),
      };

      // Send merch packet data unless explicitly skipped
      if (!this.skipMerchPacket) {
        requestData.donor_name = this.donorName.trim();
        requestData.donor_company = this.donorCompany.trim() || null;
        requestData.donor_street = this.donorStreet.trim();
        requestData.donor_street_number = this.donorStreetNumber.trim();
        requestData.donor_postcode = this.donorPostcode.trim();
        requestData.donor_city = this.donorCity.trim();
        requestData.donor_email = this.donorEmail.trim();
      }

      const result = await ajax("/vzekc-verlosung/donations", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify(requestData),
      });

      const donationId = result.donation_id;

      let template =
        this.importedRaw ??
        (this.siteSettings.vzekc_verlosung_donation_template || "");
      template = template.replace(/\[POSTCODE\]/g, this.postcode.trim());

      this.args.closeModal();

      const topicTitle = `${this.title.trim()} in ${this.postcode.trim()}`;

      this.composer.open({
        action: Composer.CREATE_TOPIC,
        categoryId: this.args.model.categoryId,
        title: topicTitle,
        reply: template,
        draftKey: `new_topic_donation_${donationId}_${Date.now()}`,
        donation_id: donationId,
        skipSimilarTopics: true,
      });
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <DModal
      @title={{i18n "vzekc_verlosung.donation_modal.title"}}
      @closeModal={{@closeModal}}
      class="create-donation-modal"
    >
      <:body>
        <form {{on "submit" this.preventSubmit}} class="donation-form">
          <label
            class="donation-email-import {{if this.isDraggingFiles 'dragging'}}"
            {{on "dragover" this.dragOver}}
            {{on "dragleave" this.dragLeave}}
            {{on "drop" this.dropFiles}}
          >
            <input
              type="file"
              accept=".eml,.zip,message/rfc822,application/zip"
              multiple
              disabled={{this.isImporting}}
              {{on "change" this.importSelectedFiles}}
              class="donation-email-import-input"
            />
            <span class="donation-email-import-label">
              {{#if this.isImporting}}
                {{i18n "vzekc_verlosung.donation_modal.email_importing"}}
              {{else}}
                {{i18n "vzekc_verlosung.donation_modal.email_import_label"}}
              {{/if}}
            </span>
            <span class="help-text">{{i18n
                "vzekc_verlosung.donation_modal.email_import_help"
              }}</span>
          </label>

          {{#if this.skippedImages.length}}
            <div class="alert alert-error donation-email-import-skipped">
              {{i18n
                "vzekc_verlosung.donation_modal.email_import_skipped_images"
                names=this.skippedImageNames
              }}
            </div>
          {{/if}}

          <div class="control-group">
            <label>{{i18n "vzekc_verlosung.donation_modal.title_label"}}</label>
            <input
              type="text"
              {{on "input" (fn this.updateField "title")}}
              {{on "keydown" this.handleKeyDown}}
              {{autoFocus}}
              value={{this.title}}
              placeholder={{i18n
                "vzekc_verlosung.donation_modal.title_placeholder"
              }}
              class="donation-title-input"
            />
          </div>

          <div class="control-group">
            <label>{{i18n
                "vzekc_verlosung.donation_modal.postcode_label"
              }}</label>
            <input
              type="text"
              {{on "input" (fn this.updateField "postcode")}}
              {{on "keydown" this.handleKeyDown}}
              value={{this.postcode}}
              placeholder={{i18n
                "vzekc_verlosung.donation_modal.postcode_placeholder"
              }}
              class="donation-postcode-input"
            />
          </div>

          <div class="control-group merch-packet-section">
            <label class="checkbox-label">
              <input
                type="checkbox"
                checked={{this.skipMerchPacket}}
                {{on "change" this.toggleSkipMerchPacket}}
              />
              {{i18n "vzekc_verlosung.donation_modal.skip_merch_packet"}}
            </label>
            {{#unless this.skipMerchPacket}}
              <p class="help-text">{{i18n
                  "vzekc_verlosung.donation_modal.merch_packet_help"
                }}</p>
            {{/unless}}
          </div>

          {{#unless this.skipMerchPacket}}
            <fieldset class="donor-address-section">
              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.donation_modal.donor_name_label"
                  }}<span class="required">*</span></label>
                <input
                  type="text"
                  {{on "input" (fn this.updateField "donorName")}}
                  {{on "keydown" this.handleKeyDown}}
                  value={{this.donorName}}
                  placeholder={{i18n
                    "vzekc_verlosung.donation_modal.donor_name_placeholder"
                  }}
                  class="donor-name-input"
                />
              </div>

              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.donation_modal.donor_company_label"
                  }}</label>
                <input
                  type="text"
                  {{on "input" (fn this.updateField "donorCompany")}}
                  {{on "keydown" this.handleKeyDown}}
                  value={{this.donorCompany}}
                  placeholder={{i18n
                    "vzekc_verlosung.donation_modal.donor_company_placeholder"
                  }}
                  class="donor-company-input"
                />
              </div>

              <div class="control-group street-row">
                <div class="street-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_street_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorStreet")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorStreet}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_street_placeholder"
                    }}
                    class="donor-street-input"
                  />
                </div>
                <div class="street-number-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_street_number_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorStreetNumber")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorStreetNumber}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_street_number_placeholder"
                    }}
                    class="donor-street-number-input"
                  />
                </div>
              </div>

              <div class="control-group postal-row">
                <div class="postcode-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_postcode_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorPostcode")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorPostcode}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_postcode_placeholder"
                    }}
                    class="donor-postcode-input"
                  />
                </div>
                <div class="city-field">
                  <label>{{i18n
                      "vzekc_verlosung.donation_modal.donor_city_label"
                    }}<span class="required">*</span></label>
                  <input
                    type="text"
                    {{on "input" (fn this.updateField "donorCity")}}
                    {{on "keydown" this.handleKeyDown}}
                    value={{this.donorCity}}
                    placeholder={{i18n
                      "vzekc_verlosung.donation_modal.donor_city_placeholder"
                    }}
                    class="donor-city-input"
                  />
                </div>
              </div>

              <div class="control-group">
                <label>{{i18n
                    "vzekc_verlosung.donation_modal.donor_email_required_label"
                  }}<span class="required">*</span></label>
                <input
                  type="email"
                  name="email"
                  autocomplete="email"
                  required
                  {{on "input" (fn this.updateField "donorEmail")}}
                  {{on "keydown" this.handleKeyDown}}
                  value={{this.donorEmail}}
                  placeholder={{i18n
                    "vzekc_verlosung.donation_modal.donor_email_placeholder"
                  }}
                  class="donor-email-input"
                />
                <p class="help-text">{{i18n
                    "vzekc_verlosung.donation_modal.donor_email_required_help"
                  }}</p>
              </div>
            </fieldset>
          {{/unless}}

          {{#if this.importedMessages.length}}
            <section class="donation-imported-messages">
              <h3>{{i18n
                  "vzekc_verlosung.donation_modal.email_import_messages"
                }}</h3>
              {{#each this.importedMessages as |message|}}
                <details
                  open={{message.donor}}
                  class="donation-imported-message
                    {{if message.donor 'from-donor' 'from-facilitator'}}"
                >
                  <summary>
                    <span class="message-from">{{message.from}}</span>
                    <span class="message-date">{{message.displayDate}}</span>
                  </summary>
                  <pre class="message-text">{{message.text}}</pre>
                </details>
              {{/each}}
            </section>
          {{/if}}
        </form>
      </:body>
      <:footer>
        <DButton
          @action={{this.submit}}
          @label={{this.submitLabelKey}}
          @icon={{this.submitIcon}}
          @disabled={{not this.canSubmit}}
          class="btn-primary"
        />
      </:footer>
    </DModal>
  </template>
}
