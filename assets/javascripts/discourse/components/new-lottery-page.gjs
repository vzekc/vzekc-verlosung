import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn, hash } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
// eslint-disable-next-line no-unused-vars
import { readonly } from "@ember/object/computed";
import { getOwner } from "@ember/owner";
import { cancel } from "@ember/runloop";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DEditor from "discourse/components/d-editor";
import Form from "discourse/components/form";
import PickFilesButton from "discourse/components/pick-files-button";
import DTooltip from "discourse/float-kit/components/d-tooltip";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import discourseDebounce from "discourse/lib/debounce";
import { authorizesOneOrMoreImageExtensions } from "discourse/lib/uploads";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import Draft from "discourse/models/draft";
import { eq, gt } from "discourse/truth-helpers";
import { i18n } from "discourse-i18n";

/**
 * Full-page lottery creation form
 * Uses DEditor for post body with image upload support
 * Creates topic directly via API without using composer
 *
 * @component NewLotteryPage
 * @param {Object} [model] - Route model with optional donation data
 * @param {number} [model.donationId] - ID of donation to link lottery to
 * @param {string} [model.donationTitle] - Title from donation to pre-fill
 */
export default class NewLotteryPage extends Component {
  // Auto-save delay in milliseconds
  static DRAFT_SAVE_DELAY = 2000;

  @service router;
  @service siteSettings;
  @service currentUser;
  @service dialog;
  @service site;

  @tracked title = "";
  @tracked body = "";
  @tracked durationDays = 14;
  @tracked drawingMode = "automatic";
  @tracked packetMode = "mehrere"; // "ein" or "mehrere"
  @tracked noAbholerpaket = false;
  @tracked abholerpaketTitle = "";
  @tracked singlePacketErhaltungsberichtNotRequired = false;
  @tracked packets = [];
  @tracked isSubmitting = false;
  @tracked draftSequence = 0;
  @tracked draftSaving = false;
  @tracked draftLoaded = false;
  @tracked donationId = null;

  formApi = null;
  bodyFileInputId = "lottery-body-file-uploader";

  // Stable form data object - avoids re-initialization on tracked property changes
  _formData = null;

  // Packet uploaders - one per packet index
  _packetUploaders = {};

  // Auto-save debounce timer
  _saveDraftDebounce = null;
  _saveDraftPromise = null;

  get formData() {
    if (!this._formData) {
      this._formData = {
        title: this.title,
        body: this.body,
        durationDays: this.durationDays,
        drawingMode: this.drawingMode,
      };
    }
    return this._formData;
  }

  constructor() {
    super(...arguments);
    // Initialize packets based on mode
    // Default mode is "mehrere" with one regular packet (Paket 1)
    this.initializePackets();
    // Set initial body to template
    this.body = this.template;

    // Pre-fill from donation if provided via route model
    if (this.args.model?.donationId) {
      this.donationId = this.args.model.donationId;
    }
    if (this.args.model?.donationTitle) {
      this.title = this.args.model.donationTitle;
    }

    // Load draft asynchronously (only if not creating from donation)
    if (!this.donationId) {
      this.loadDraft();
    } else {
      this.draftLoaded = true;
    }

    // Set up upload handler for body editor
    this.uppyUpload = new UppyUpload(getOwner(this), {
      id: "lottery-body-uploader",
      type: "composer",
      uploadDone: (upload) => {
        this.insertUploadMarkdown(upload);
      },
    });
  }

  willDestroy() {
    super.willDestroy(...arguments);
    // Cancel debounce timer and save draft immediately if there are pending changes
    if (this._saveDraftDebounce) {
      cancel(this._saveDraftDebounce);
      this._performDraftSave();
    }
  }

  get allowUpload() {
    return authorizesOneOrMoreImageExtensions(
      this.currentUser?.staff,
      this.siteSettings
    );
  }

  get uploadIcon() {
    return authorizesOneOrMoreImageExtensions(
      this.currentUser?.staff,
      this.siteSettings
    )
      ? "far-image"
      : "upload";
  }

  insertUploadMarkdown(upload) {
    const markdown = this.buildUploadMarkdown(upload);
    // Get current body from form API (preferred) or tracked property
    const currentBody = this.formApi?.get("body") || this.body || "";
    let newBody;
    if (currentBody && !currentBody.endsWith("\n")) {
      newBody = currentBody + "\n" + markdown + "\n";
    } else {
      newBody = currentBody + markdown + "\n";
    }
    // Only update via formApi to avoid triggering form re-initialization
    if (this.formApi) {
      this.formApi.set("body", newBody);
    }
    // Keep tracked property in sync for draft saving
    this.body = newBody;
    this._scheduleDraftSave();
  }

  buildUploadMarkdown(upload) {
    const ext = upload.extension || upload.url.split(".").pop();
    const imageExts = ["jpg", "jpeg", "png", "gif", "webp", "avif", "svg"];

    if (imageExts.includes(ext?.toLowerCase())) {
      return `![${upload.original_filename}|${upload.width}x${upload.height}](${upload.short_url})`;
    } else {
      return `[${upload.original_filename}|attachment](${upload.short_url}) (${upload.human_filesize})`;
    }
  }

  @action
  extraButtons(toolbar) {
    if (this.allowUpload && this.site.desktopView) {
      toolbar.addButton({
        id: "upload",
        group: "insertions",
        icon: this.uploadIcon,
        title: "upload",
        sendAction: () => this.showUploadModal(),
      });
    }
  }

  @action
  showUploadModal() {
    document.getElementById(this.bodyFileInputId)?.click();
  }

  // ===== PACKET UPLOAD METHODS =====

  getPacketFileInputId(index) {
    return `lottery-packet-${index}-file-uploader`;
  }

  @action
  packetExtraButtons(index) {
    return (toolbar) => {
      if (this.allowUpload && this.site.desktopView) {
        toolbar.addButton({
          id: "upload",
          group: "insertions",
          icon: this.uploadIcon,
          title: "upload",
          sendAction: () => this.showPacketUploadModal(index),
        });
      }
    };
  }

  @action
  showPacketUploadModal(index) {
    const inputId = this.getPacketFileInputId(index);
    document.getElementById(inputId)?.click();
  }

  @action
  registerPacketFileInput(index, fileInputEl) {
    if (!this._packetUploaders[index]) {
      this._packetUploaders[index] = new UppyUpload(getOwner(this), {
        id: `lottery-packet-${index}-uploader`,
        type: "composer",
        uploadDone: (upload) => {
          this.insertPacketUploadMarkdown(index, upload);
        },
      });
    }
    this._packetUploaders[index].setup(fileInputEl);
  }

  insertPacketUploadMarkdown(index, upload) {
    const markdown = this.buildUploadMarkdown(upload);
    const packet = this.packets[index];
    if (packet) {
      const currentRaw = packet.raw || "";
      const newRaw =
        currentRaw && !currentRaw.endsWith("\n")
          ? currentRaw + "\n" + markdown + "\n"
          : currentRaw + markdown + "\n";

      // Create new packet object to trigger Glimmer reactivity
      this.packets = this.packets.map((p, i) =>
        i === index ? { ...p, raw: newRaw } : p
      );
      this._scheduleDraftSave();
    }
  }

  /**
   * Initialize packets array based on packet mode and abholerpaket settings
   */
  initializePackets() {
    if (this.packetMode === "ein") {
      // Ein Paket mode: no packet posts needed
      this.packets = [];
    } else {
      // Mehrere Pakete mode
      if (!this.noAbholerpaket) {
        // With Abholerpaket: start with Paket 0 (Abholerpaket) and Paket 1
        this.packets = [
          {
            title: "",
            raw: "",
            erhaltungsberichtNotRequired: false,
            isAbholerpaket: true,
            ordinal: 0,
          },
          {
            title: "",
            raw: "",
            erhaltungsberichtNotRequired: false,
            ordinal: 1,
          },
        ];
      } else {
        // Without Abholerpaket: start with just Paket 1
        this.packets = [
          {
            title: "",
            raw: "",
            erhaltungsberichtNotRequired: false,
            ordinal: 1,
          },
        ];
      }
    }
  }

  @action
  registerFormApi(api) {
    this.formApi = api;
  }

  get drawingModeOptions() {
    return [
      {
        value: "automatic",
        name: i18n("vzekc_verlosung.composer.drawing_mode_automatic"),
      },
      {
        value: "manual",
        name: i18n("vzekc_verlosung.composer.drawing_mode_manual"),
      },
    ];
  }

  get lotteryCategoryId() {
    return parseInt(this.siteSettings.vzekc_verlosung_category_id, 10);
  }

  get template() {
    const rawTemplate = i18n("vzekc_verlosung.composer.template");
    const drawingModeText = i18n(
      "vzekc_verlosung.composer.drawing_mode_automatic"
    );

    return rawTemplate
      .replace("{duration}", "14")
      .replace("{drawing_mode}", drawingModeText.toLowerCase());
  }

  /**
   * Creates an empty packet object with the given ordinal
   */
  createEmptyPacket(ordinal) {
    return {
      title: "",
      raw: "",
      erhaltungsberichtNotRequired: false,
      ordinal,
    };
  }

  /**
   * Get packet number for display (1-indexed)
   */
  getPacketNumber(index) {
    return index + 1;
  }

  /**
   * Check if a packet can be removed
   * - Abholerpaket (isAbholerpaket: true) cannot be removed
   * - Must have at least 1 packet in mehrere mode
   */
  @action
  canRemovePacket(packet) {
    // Cannot remove Abholerpaket
    if (packet.isAbholerpaket) {
      return false;
    }

    // In mehrere mode, must keep at least 1 non-Abholerpaket packet
    const nonAbholerpaketCount = this.packets.filter(
      (p) => !p.isAbholerpaket
    ).length;
    return nonAbholerpaketCount > 1;
  }

  @action
  handleBodyChange(value) {
    this.body = value;
    this._scheduleDraftSave();
  }

  /**
   * Wrapper for body editor changes - updates form field and triggers auto-save
   */
  @action
  handleBodyFieldChange(fieldSetter, event) {
    fieldSetter(event);
    this._scheduleDraftSave();
  }

  /**
   * Trigger auto-save when FormKit fields change
   */
  @action
  onFormFieldChange() {
    this._scheduleDraftSave();
  }

  @action
  validateDuration(name, value, { addError }) {
    const duration = parseInt(value, 10);
    if (isNaN(duration) || duration < 7 || duration > 28) {
      addError(name, {
        title: i18n("vzekc_verlosung.composer.duration_label"),
        message: i18n("vzekc_verlosung.composer.duration_hint"),
      });
    }
  }

  @action
  addPacket() {
    // Calculate next ordinal: find max ordinal and add 1
    const maxOrdinal = Math.max(...this.packets.map((p) => p.ordinal || 0), 0);
    const nextOrdinal = maxOrdinal + 1;
    this.packets = [...this.packets, this.createEmptyPacket(nextOrdinal)];
    this._scheduleDraftSave();
  }

  @action
  removePacket(index) {
    if (this.packets.length > 1) {
      this.packets = this.packets.filter((_, i) => i !== index);
      this._scheduleDraftSave();
    }
  }

  @action
  updatePacket(index, field, event) {
    const value =
      event.target.type === "checkbox"
        ? event.target.checked
        : event.target.value;
    this.packets[index][field] = value;
    this.packets = [...this.packets];
    this._scheduleDraftSave();
  }

  @action
  updatePacketRaw(index, value) {
    // DEditor passes the new value directly (not an event object)
    this.packets[index].raw = value;
    this.packets = [...this.packets];
    this._scheduleDraftSave();
  }

  @action
  updateField(field, event) {
    this[field] = event.target.value;
    this._scheduleDraftSave();
  }

  @action
  toggleNoAbholerpaket(event) {
    this.noAbholerpaket = event.target.checked;
    // Reinitialize packets when Abholerpaket toggle changes
    this.initializePackets();
    this._scheduleDraftSave();
  }

  @action
  toggleSinglePacketErhaltungsbericht(event) {
    this.singlePacketErhaltungsberichtNotRequired = event.target.checked;
    this._scheduleDraftSave();
  }

  /**
   * Switch between Ein Paket and Mehrere Pakete modes
   * Warns user if they have unsaved content
   */
  @action
  async switchPacketMode(newMode, event) {
    // Don't switch if already in this mode
    if (this.packetMode === newMode) {
      return;
    }

    // Check if user has made changes that would be lost
    const hasChanges = this.hasUnsavedPacketChanges();

    if (hasChanges) {
      // Prevent the radio button from changing before confirmation
      event?.preventDefault();

      const confirmed = await this.dialog.confirm({
        message: i18n("vzekc_verlosung.modal.switch_mode_warning_message"),
        title: i18n("vzekc_verlosung.modal.switch_mode_warning_title"),
      });
      if (!confirmed) {
        return;
      }
    }

    // Switch mode
    this.packetMode = newMode;
    // Reinitialize packets for new mode
    this.initializePackets();
    this._scheduleDraftSave();
  }

  /**
   * Check if user has unsaved packet changes in "mehrere pakete" mode
   * Only checks packets, not main body - the main body is shared between modes
   */
  hasUnsavedPacketChanges() {
    // Check all packets for user-entered content
    return this.packets.some(
      (packet) =>
        (packet.title && packet.title.trim().length > 0) ||
        (packet.raw && packet.raw.trim().length > 0)
    );
  }

  /**
   * Load existing draft if available
   */
  async loadDraft() {
    try {
      const draftKey = "new_topic";
      const result = await Draft.get(draftKey);

      if (result && result.draft) {
        const draft =
          typeof result.draft === "string"
            ? JSON.parse(result.draft)
            : result.draft;

        // Check if this is a lottery draft by looking for lottery metadata
        if (draft.metaData && draft.metaData.lottery_duration_days) {
          this.title = draft.title || "";
          // Ensure body is always a string
          this.body =
            typeof draft.reply === "string" && draft.reply
              ? draft.reply
              : this.template;
          this.durationDays = draft.metaData.lottery_duration_days || 14;
          this.drawingMode = draft.metaData.lottery_drawing_mode || "automatic";
          this.draftSequence = result.draft_sequence || 0;

          // Update the stable form data object
          if (this._formData) {
            this._formData.title = this.title;
            this._formData.body = this.body;
            this._formData.durationDays = this.durationDays;
            this._formData.drawingMode = this.drawingMode;
          }

          // Load packet mode (default to "mehrere" for backward compatibility)
          this.packetMode = draft.metaData.packet_mode || "mehrere";

          // Load single packet settings (Ein Paket mode)
          if (
            draft.metaData.single_packet_erhaltungsbericht_not_required !==
            undefined
          ) {
            this.singlePacketErhaltungsberichtNotRequired =
              draft.metaData.single_packet_erhaltungsbericht_not_required;
          }

          // Load packet data if available (Mehrere Pakete mode)
          if (draft.metaData.lottery_packets) {
            this.packets = draft.metaData.lottery_packets;
          }

          // Load abholerpaket data (Mehrere Pakete mode)
          if (draft.metaData.has_abholerpaket !== undefined) {
            this.noAbholerpaket = !draft.metaData.has_abholerpaket;
            this.abholerpaketTitle = draft.metaData.abholerpaket_title || "";
          }

          // Update form values using the form API if available
          if (this.formApi) {
            this.formApi.set("title", this.title);
            this.formApi.set("body", this.body);
            this.formApi.set("durationDays", this.durationDays);
            this.formApi.set("drawingMode", this.drawingMode);
          }
        }
      }
    } catch (error) {
      // Silently fail if draft loading fails
      // eslint-disable-next-line no-console
      console.warn("Failed to load lottery draft:", error);
    } finally {
      this.draftLoaded = true;
    }
  }

  /**
   * Schedule a draft save with debouncing
   * Called automatically when form data changes
   */
  _scheduleDraftSave() {
    // Don't auto-save if creating from donation (no draft needed)
    if (this.donationId) {
      return;
    }

    // Don't schedule if draft hasn't loaded yet
    if (!this.draftLoaded) {
      return;
    }

    cancel(this._saveDraftDebounce);
    this._saveDraftDebounce = discourseDebounce(
      this,
      this._performDraftSave,
      NewLotteryPage.DRAFT_SAVE_DELAY
    );
  }

  /**
   * Perform the actual draft save
   */
  async _performDraftSave() {
    // Don't save if already saving
    if (this._saveDraftPromise) {
      // Re-schedule if a change happened during save
      this._scheduleDraftSave();
      return;
    }

    this.draftSaving = true;

    try {
      // Get current form values from the form API
      const title = this.formApi?.get("title") || this.title;
      const body = this.formApi?.get("body") || this.body;
      const durationDays =
        this.formApi?.get("durationDays") || this.durationDays;
      const drawingMode = this.formApi?.get("drawingMode") || this.drawingMode;

      // Normalize packet data to ensure we only save strings and include all fields
      const normalizedPackets = this.packets.map((packet) => ({
        title: typeof packet.title === "string" ? packet.title : "",
        raw: typeof packet.raw === "string" ? packet.raw : "",
        erhaltungsberichtNotRequired: packet.erhaltungsberichtNotRequired,
        ordinal: packet.ordinal,
        isAbholerpaket: packet.isAbholerpaket || false,
      }));

      const draftData = {
        reply: body,
        title,
        categoryId: this.lotteryCategoryId,
        action: "createTopic",
        metaData: {
          lottery_duration_days: durationDays,
          lottery_drawing_mode: drawingMode,
          packet_mode: this.packetMode,
          lottery_packets: normalizedPackets,
          single_packet_erhaltungsbericht_not_required:
            this.singlePacketErhaltungsberichtNotRequired,
          has_abholerpaket: !this.noAbholerpaket,
          abholerpaket_title: this.abholerpaketTitle,
        },
      };

      this._saveDraftPromise = Draft.save(
        "new_topic",
        this.draftSequence,
        draftData,
        this.currentUser.id,
        { forceSave: true }
      );

      const result = await this._saveDraftPromise;
      // Update sequence number from response to avoid conflicts on next save
      if (result && result.draft_sequence !== undefined) {
        this.draftSequence = result.draft_sequence;
      }
    } catch {
      // Silently fail for auto-save - don't interrupt user
    } finally {
      this._saveDraftPromise = null;
      this.draftSaving = false;
    }
  }

  /**
   * Discard saved draft
   */
  @action
  async discardDraft() {
    try {
      // Fetch the current draft to get the correct sequence number
      const draftResult = await Draft.get("new_topic");
      if (draftResult && draftResult.draft_sequence !== undefined) {
        await Draft.clear("new_topic", draftResult.draft_sequence);
      }
      this.draftSequence = 0;
      // Reset form to defaults
      this.title = "";
      this.body = this.template;
      this.durationDays = 14;
      this.drawingMode = "automatic";
      this.noAbholerpaket = false;
      this.abholerpaketTitle = "";
      this.abholerpaketErhaltungsberichtNotRequired = false;
      this.packets = [
        { raw: "# Paket 1\n\n", erhaltungsberichtNotRequired: false },
      ];
    } catch (error) {
      popupAjaxError(error);
    }
  }

  @action
  async submit(data) {
    this.isSubmitting = true;

    try {
      let packets = [];

      if (this.packetMode === "mehrere") {
        // Mehrere Pakete mode: validate that all packets have titles
        const invalidPacket = this.packets.find(
          (packet) => !packet.title || packet.title.trim().length === 0
        );
        if (invalidPacket) {
          popupAjaxError(
            new Error(i18n("vzekc_verlosung.errors.packet_title_required"))
          );
          this.isSubmitting = false;
          return;
        }

        // Prepare packet data - include all packets with their ordinals
        packets = this.packets.map((packet) => ({
          title: packet.title.trim(),
          raw: packet.raw.trim(),
          ordinal: packet.ordinal,
          erhaltungsbericht_required: !packet.erhaltungsberichtNotRequired,
          is_abholerpaket: packet.isAbholerpaket || false,
        }));

        // Validate that at least one packet has content (title is required, raw is optional)
        if (packets.length === 0) {
          popupAjaxError(
            new Error(
              i18n("vzekc_verlosung.errors.at_least_one_packet_required")
            )
          );
          this.isSubmitting = false;
          return;
        }
      }

      // Build request data based on packet mode
      const requestData = {
        title: data.title,
        raw: data.body,
        category_id: this.lotteryCategoryId,
        duration_days: data.durationDays,
        drawing_mode: data.drawingMode,
        packet_mode: this.packetMode,
        packets,
      };

      if (this.packetMode === "ein") {
        // Ein Paket mode: send single packet settings
        requestData.single_packet_erhaltungsbericht_required =
          !this.singlePacketErhaltungsberichtNotRequired;
        requestData.has_abholerpaket = false;
      } else {
        // Mehrere Pakete mode: send abholerpaket settings
        requestData.has_abholerpaket = !this.noAbholerpaket;
        // Abholerpaket title is now part of the packets array if it exists
      }

      // Include donation_id if creating lottery from donation
      if (this.donationId) {
        requestData.donation_id = this.donationId;
      }

      const response = await ajax("/vzekc-verlosung/lotteries", {
        type: "POST",
        contentType: "application/json",
        data: JSON.stringify(requestData),
      });

      // Always clear the draft after successful publish
      // Fetch the current draft to get the correct sequence number
      try {
        const draftResult = await Draft.get("new_topic");
        if (draftResult && draftResult.draft_sequence !== undefined) {
          await Draft.clear("new_topic", draftResult.draft_sequence);
        }
      } catch {
        // Ignore errors when clearing draft
      }

      // Navigate to the created topic
      if (response.main_topic) {
        this.router.transitionTo(
          "topic",
          response.main_topic.slug,
          response.main_topic.id
        );
      }
    } catch (error) {
      popupAjaxError(error);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <div class="new-lottery-page">
      <div class="new-lottery-page__header">
        <h1>{{i18n "vzekc_verlosung.neue_verlosung"}}</h1>
      </div>

      {{#if this.draftLoaded}}
        <Form
          @onSubmit={{this.submit}}
          @onRegisterApi={{this.registerFormApi}}
          @data={{this.formData}}
          as |form|
        >
        <div class="lottery-title-field">
          <form.Field
            @name="title"
            @title={{i18n "vzekc_verlosung.composer.title_label"}}
            @validation="required"
            as |field|
          >
            <field.Input
              placeholder={{i18n "vzekc_verlosung.composer.title_placeholder"}}
              {{on "input" this.onFormFieldChange}}
            />
          </form.Field>
        </div>

        <div class="lottery-params-grid">
          <form.Field
            @name="durationDays"
            @title={{i18n "vzekc_verlosung.composer.duration_label"}}
            @validation="required|integer"
            @validate={{this.validateDuration}}
            as |field|
          >
            <div class="lottery-param-wrapper">
              <div class="field-title-with-tooltip">
                <label>{{i18n
                    "vzekc_verlosung.composer.duration_label"
                  }}</label>
                <DTooltip
                  @icon="circle-question"
                  @content={{i18n "vzekc_verlosung.composer.duration_hint"}}
                />
              </div>
              <field.Input
                @type="number"
                {{on "input" this.onFormFieldChange}}
              />
            </div>
          </form.Field>

          <form.Field
            @name="drawingMode"
            @title={{i18n "vzekc_verlosung.composer.drawing_mode_label"}}
            @validation="required"
            as |field|
          >
            <div class="lottery-param-wrapper">
              <div class="field-title-with-tooltip">
                <label>{{i18n
                    "vzekc_verlosung.composer.drawing_mode_label"
                  }}</label>
                <DTooltip
                  @icon="circle-question"
                  @content={{i18n "vzekc_verlosung.composer.drawing_mode_hint"}}
                />
              </div>
              <field.Select {{on "change" this.onFormFieldChange}} as |select|>
                {{#each this.drawingModeOptions as |option|}}
                  <select.Option @value={{option.value}}>
                    {{option.name}}
                  </select.Option>
                {{/each}}
              </field.Select>
            </div>
          </form.Field>
        </div>

        <form.Field
          @name="body"
          @title={{i18n "vzekc_verlosung.composer.body_label"}}
          @validation="required"
          as |field|
        >
          <div class="lottery-body-editor">
            <DEditor
              @value={{readonly field.value}}
              @change={{fn this.handleBodyFieldChange field.set}}
              @extraButtons={{this.extraButtons}}
              class="form-kit__control-composer"
              style="height: 500px"
            />
            <PickFilesButton
              @registerFileInput={{this.uppyUpload.setup}}
              @fileInputId={{this.bodyFileInputId}}
              @acceptedFormatsOverride="image/*"
            />
          </div>
        </form.Field>

        <div class="lottery-paket-setup-section">
          <h3>{{i18n "vzekc_verlosung.modal.paket_setup_label"}}</h3>

          <div class="packet-mode-selection">
            <label class="packet-mode-label">
              {{i18n "vzekc_verlosung.modal.packet_mode_label"}}
            </label>
            <div class="packet-mode-options">
              <label class="radio-label">
                <input
                  type="radio"
                  name="packetMode"
                  value="ein"
                  checked={{eq this.packetMode "ein"}}
                  {{on "click" (fn this.switchPacketMode "ein")}}
                />
                <span class="radio-text">
                  {{i18n "vzekc_verlosung.modal.packet_mode_ein"}}
                </span>
                <span class="radio-help">
                  {{i18n "vzekc_verlosung.modal.packet_mode_ein_help"}}
                </span>
              </label>
              {{#if (eq this.packetMode "ein")}}
                <div class="single-packet-settings">
                  <label class="checkbox-label">
                    <input
                      type="checkbox"
                      {{on "change" this.toggleSinglePacketErhaltungsbericht}}
                      checked={{this.singlePacketErhaltungsberichtNotRequired}}
                    />
                    {{i18n
                      "vzekc_verlosung.modal.single_packet_erhaltungsbericht_label"
                    }}
                  </label>
                </div>
              {{/if}}
              <label class="radio-label">
                <input
                  type="radio"
                  name="packetMode"
                  value="mehrere"
                  checked={{eq this.packetMode "mehrere"}}
                  {{on "click" (fn this.switchPacketMode "mehrere")}}
                />
                <span class="radio-text">
                  {{i18n "vzekc_verlosung.modal.packet_mode_mehrere"}}
                </span>
                <span class="radio-help">
                  {{i18n "vzekc_verlosung.modal.packet_mode_mehrere_help"}}
                </span>
              </label>
            </div>
          </div>

          {{#if (eq this.packetMode "mehrere")}}
            <div class="multiple-packets-settings">
              <label class="checkbox-label">
                <input
                  type="checkbox"
                  {{on "change" this.toggleNoAbholerpaket}}
                  checked={{this.noAbholerpaket}}
                />
                {{i18n "vzekc_verlosung.modal.no_abholerpaket_label"}}
              </label>
              <div class="abholerpaket-help">
                {{i18n "vzekc_verlosung.modal.no_abholerpaket_help"}}
              </div>
            </div>
          {{/if}}
        </div>

        {{#if (eq this.packetMode "mehrere")}}
          <div class="lottery-packets-section">
            <h3>{{i18n "vzekc_verlosung.modal.packets_label"}}</h3>
            <div class="packets-list">
              {{#each this.packets as |packet index|}}
                <div
                  class="packet-item
                    {{if packet.isAbholerpaket 'is-abholerpaket'}}"
                >
                  <div class="packet-header">
                    {{#if packet.isAbholerpaket}}
                      <h4>
                        {{i18n "vzekc_verlosung.modal.abholerpaket_badge"}}
                      </h4>
                    {{else}}
                      <h4>Paket {{packet.ordinal}}</h4>
                    {{/if}}
                    {{#if (this.canRemovePacket packet)}}
                      <DButton
                        @action={{fn this.removePacket index}}
                        @icon="trash-can"
                        @title="vzekc_verlosung.modal.remove_packet"
                        class="btn-danger btn-small"
                      />
                    {{/if}}
                  </div>
                  <div class="packet-title-input">
                    <input
                      type="text"
                      value={{packet.title}}
                      {{on "input" (fn this.updatePacket index "title")}}
                      placeholder={{i18n
                        "vzekc_verlosung.modal.packet_title_placeholder"
                        number=(this.getPacketNumber index)
                      }}
                      class="packet-title-field"
                    />
                  </div>
                  <div class="packet-editor">
                    <DEditor
                      @value={{readonly packet.raw}}
                      @change={{fn this.updatePacketRaw index}}
                      @extraButtons={{this.packetExtraButtons index}}
                      @preview={{false}}
                      @placeholder="vzekc_verlosung.modal.packet_description_placeholder"
                    />
                    <PickFilesButton
                      @registerFileInput={{fn
                        this.registerPacketFileInput
                        index
                      }}
                      @fileInputId={{this.getPacketFileInputId index}}
                      @acceptedFormatsOverride="image/*"
                    />
                  </div>
                  <div class="packet-checkbox-group">
                    <label class="checkbox-label">
                      <input
                        type="checkbox"
                        {{on
                          "change"
                          (fn
                            this.updatePacket
                            index
                            "erhaltungsberichtNotRequired"
                          )
                        }}
                        checked={{packet.erhaltungsberichtNotRequired}}
                      />
                      {{i18n
                        "vzekc_verlosung.modal.erhaltungsbericht_required_label"
                      }}
                    </label>
                  </div>
                </div>
              {{/each}}
            </div>

            <DButton
              @action={{this.addPacket}}
              @icon="plus"
              @label="vzekc_verlosung.modal.add_packet"
              class="btn-default"
            />
          </div>
        {{/if}}

        <div class="lottery-form-actions">
          {{#if this.draftSaving}}
            <div class="lottery-draft-saving-notice">
              {{i18n "vzekc_verlosung.draft_saving"}}
            </div>
          {{/if}}

          <div class="lottery-action-buttons">
            <form.Submit
              @label="vzekc_verlosung.publish_lottery"
              @disabled={{this.isSubmitting}}
            />

            {{#if (gt this.draftSequence 0)}}
              <DButton
                @action={{this.discardDraft}}
                @label="vzekc_verlosung.discard_draft"
                @disabled={{this.isSubmitting}}
                class="btn-danger"
              />
            {{/if}}
          </div>
        </div>
        </Form>
      {{/if}}
    </div>
  </template>
}
