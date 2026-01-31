import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { fn } from "@ember/helper";
import { on } from "@ember/modifier";
import { action } from "@ember/object";
// eslint-disable-next-line no-unused-vars
import { readonly } from "@ember/object/computed";
import { getOwner } from "@ember/owner";
import didInsert from "@ember/render-modifiers/modifiers/did-insert";
import willDestroy from "@ember/render-modifiers/modifiers/will-destroy";
import { cancel } from "@ember/runloop";
import { service } from "@ember/service";
import DButton from "discourse/components/d-button";
import DEditor from "discourse/components/d-editor";
import Form from "discourse/components/form";
import icon from "discourse/helpers/d-icon";
import PickFilesButton from "discourse/components/pick-files-button";
import DTooltip from "discourse/float-kit/components/d-tooltip";
import { ajax } from "discourse/lib/ajax";
import { extractError } from "discourse/lib/ajax-error";
import discourseDebounce from "discourse/lib/debounce";
import { authorizesOneOrMoreImageExtensions } from "discourse/lib/uploads";
import UppyUpload from "discourse/lib/uppy/uppy-upload";
import { clipboardHelpers } from "discourse/lib/utilities";
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
  @tracked pendingDonations = [];
  @tracked pendingDonationsLoaded = false;

  formApi = null;
  bodyFileInputId = "lottery-body-file-uploader";

  // Stable form data object - avoids re-initialization on tracked property changes
  _formData = null;

  // Packet uploaders - one per packet index
  _packetUploaders = {};

  // Auto-save debounce timer
  _saveDraftDebounce = null;
  _saveDraftPromise = null;

  // Packet paste handlers - keyed by packet index
  _packetPasteHandlers = {};

  // TextManipulation objects from DEditor for placeholder handling
  _bodyTextManipulation = null;
  _packetTextManipulations = {};

  // Track Uppy files by name to match with upload completion
  _bodyUppyFiles = new Map();
  _packetUppyFiles = {};

  // Flag to prevent draft save after successful publish
  _publishedSuccessfully = false;

  constructor() {
    super(...arguments);
    // Initialize packets based on mode
    // Default mode is "mehrere" with one regular packet (Paket 1)
    this.initializePackets();
    // Set initial body to template
    this.body = this.template;

    // Pre-fill from donation if provided via route model
    // These values from URL params take precedence over draft values
    if (this.args.model?.donationId) {
      this.donationId = this.args.model.donationId;
    }
    if (this.args.model?.donationTitle) {
      this.title = this.args.model.donationTitle;
    }

    // Always attempt to load draft - it will handle donation_id conflicts
    this.loadDraft();

    // Load pending donations if no donation_id was provided
    if (!this.donationId) {
      this.loadPendingDonations();
    } else {
      this.pendingDonationsLoaded = true;
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
    // Skip saving if lottery was successfully published (draft already cleared)
    if (this._saveDraftDebounce) {
      cancel(this._saveDraftDebounce);
      if (!this._publishedSuccessfully) {
        this._performDraftSave();
      }
    }
  }

  /**
   * Set up paste event listener to handle image uploads from clipboard
   * Uses capture phase to intercept before ProseMirror handles the paste
   */
  @action
  setupBodyPasteHandler(element) {
    this._bodyEditorElement = element;
    this._bodyPasteHandler = this._handlePaste.bind(this);
    element.addEventListener("paste", this._bodyPasteHandler, {
      capture: true,
    });
  }

  /**
   * Clean up paste event listener
   */
  @action
  cleanupBodyPasteHandler(element) {
    if (this._bodyPasteHandler) {
      element.removeEventListener("paste", this._bodyPasteHandler, {
        capture: true,
      });
    }
  }

  /**
   * Capture textManipulation from DEditor for placeholder handling
   */
  @action
  onBodyEditorSetup(textManipulation) {
    this._bodyTextManipulation = textManipulation;
  }

  /**
   * Register file input and set up placeholder handlers for body editor
   */
  @action
  registerBodyFileInput(fileInputEl) {
    this.uppyUpload.setup(fileInputEl);
    this._setupBodyPlaceholderHandlers();
  }

  /**
   * Set up Uppy event handlers for placeholder insertion
   */
  _setupBodyPlaceholderHandlers() {
    const uppy = this.uppyUpload.uppyWrapper?.uppyInstance;
    if (!uppy) {
      return;
    }

    uppy.on("file-added", (file) => {
      this._bodyUppyFiles.set(file.name, file);
      if (this._bodyTextManipulation?.placeholder) {
        this._bodyTextManipulation.placeholder.insert(file);
      }
    });
  }

  /**
   * Handle paste events - upload image files instead of using URLs
   * Mimics the behavior of UppyComposerUpload._pasteEventListener
   */
  _handlePaste(event) {
    if (!this.allowUpload) {
      return;
    }

    const { canUpload, canPasteHtml } = clipboardHelpers(event, {
      siteSettings: this.siteSettings,
      canUpload: true,
    });

    // If we can upload files and clipboard has image files, handle them
    if (canUpload && !canPasteHtml && event.clipboardData?.files?.length > 0) {
      const files = [...event.clipboardData.files];
      const imageFiles = files.filter((f) => f.type.startsWith("image/"));

      if (imageFiles.length > 0) {
        event.preventDefault();
        event.stopPropagation();
        // Add files to Uppy for upload
        this.uppyUpload.addFiles(imageFiles, { pasted: true });
      }
    }
  }

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

    // Try to find the original Uppy file to replace placeholder at cursor position
    const uppyFile = this._bodyUppyFiles.get(upload.file_name);
    if (uppyFile && this._bodyTextManipulation?.placeholder) {
      this._bodyTextManipulation.placeholder.success(uppyFile, markdown);
      this._bodyUppyFiles.delete(upload.file_name);
      this._scheduleDraftSave();
      return;
    }

    // Fallback: append to end of body
    const currentBody = this.formApi?.get("body") || this.body || "";
    let newBody;
    if (currentBody && !currentBody.endsWith("\n")) {
      newBody = currentBody + "\n" + markdown + "\n";
    } else {
      newBody = currentBody + markdown + "\n";
    }
    if (this.formApi) {
      this.formApi.set("body", newBody);
    }
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
    this._setupPacketPlaceholderHandlers(index);
  }

  /**
   * Capture textManipulation from packet DEditor for placeholder handling
   */
  @action
  onPacketEditorSetup(index, textManipulation) {
    this._packetTextManipulations[index] = textManipulation;
  }

  /**
   * Set up Uppy event handlers for placeholder insertion in packet editors
   */
  _setupPacketPlaceholderHandlers(index) {
    const uploader = this._packetUploaders[index];
    const uppy = uploader?.uppyWrapper?.uppyInstance;
    if (!uppy) {
      return;
    }

    if (!this._packetUppyFiles[index]) {
      this._packetUppyFiles[index] = new Map();
    }

    uppy.on("file-added", (file) => {
      this._packetUppyFiles[index].set(file.name, file);
      const textManipulation = this._packetTextManipulations[index];
      if (textManipulation?.placeholder) {
        textManipulation.placeholder.insert(file);
      }
    });
  }

  /**
   * Set up paste handler for a specific packet editor
   */
  @action
  setupPacketPasteHandler(index, element) {
    const handler = (event) => this._handlePacketPaste(event, index);
    this._packetPasteHandlers[index] = handler;
    element.addEventListener("paste", handler, { capture: true });
  }

  /**
   * Clean up paste handler for a specific packet editor
   */
  @action
  cleanupPacketPasteHandler(index, element) {
    const handler = this._packetPasteHandlers[index];
    if (handler) {
      element.removeEventListener("paste", handler, { capture: true });
      delete this._packetPasteHandlers[index];
    }
  }

  /**
   * Handle paste events for packet editors
   */
  _handlePacketPaste(event, index) {
    if (!this.allowUpload) {
      return;
    }

    const { canUpload, canPasteHtml } = clipboardHelpers(event, {
      siteSettings: this.siteSettings,
      canUpload: true,
    });

    if (canUpload && !canPasteHtml && event.clipboardData?.files?.length > 0) {
      const files = [...event.clipboardData.files];
      const imageFiles = files.filter((f) => f.type.startsWith("image/"));

      if (imageFiles.length > 0) {
        event.preventDefault();
        event.stopPropagation();
        // Add files to the packet's Uppy uploader
        const uploader = this._packetUploaders[index];
        if (uploader) {
          uploader.addFiles(imageFiles);
        }
      }
    }
  }

  insertPacketUploadMarkdown(index, upload) {
    const markdown = this.buildUploadMarkdown(upload);
    const packet = this.packets[index];
    if (!packet) {
      return;
    }

    // Try to find the original Uppy file to replace placeholder at cursor position
    const uppyFiles = this._packetUppyFiles[index];
    const uppyFile = uppyFiles?.get(upload.file_name);
    const textManipulation = this._packetTextManipulations[index];

    if (uppyFile && textManipulation?.placeholder) {
      textManipulation.placeholder.success(uppyFile, markdown);
      uppyFiles.delete(upload.file_name);
      this._scheduleDraftSave();
      return;
    }

    // Fallback: append to end
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
            quantity: 1, // Abholerpaket always has quantity 1
            isAbholerpaket: true,
            ordinal: 0,
          },
          {
            title: "",
            raw: "",
            erhaltungsberichtNotRequired: false,
            quantity: 1,
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
            quantity: 1,
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
      quantity: 1,
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
   * DEditor passes an event-like object { target: { value } } to @change
   */
  @action
  handleBodyFieldChange(fieldSetter, event) {
    fieldSetter(event.target.value);
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
  updatePacketRaw(index, event) {
    // DEditor passes an event-like object { target: { value } } to @change
    this.packets[index].raw = event.target.value;
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
   * Check if a draft has meaningful content worth preserving
   */
  _draftHasContent(draft) {
    // Check title
    if (draft.title && draft.title.trim().length > 0) {
      return true;
    }
    // Check body (compare against template to see if user made changes)
    if (draft.reply && draft.reply.trim() !== this.template.trim()) {
      return true;
    }
    // Check packets
    if (draft.metaData?.lottery_packets) {
      const hasPacketContent = draft.metaData.lottery_packets.some(
        (p) =>
          (p.title && p.title.trim().length > 0) ||
          (p.raw && p.raw.trim().length > 0)
      );
      if (hasPacketContent) {
        return true;
      }
    }
    return false;
  }

  /**
   * Load pending donations for the current user
   * These are donations where the user is the picker and hasn't completed the required action
   */
  async loadPendingDonations() {
    try {
      const response = await ajax("/vzekc-verlosung/donations/pending");
      this.pendingDonations = response.donations || [];
    } catch (error) {
      // Silently fail - not critical
      // eslint-disable-next-line no-console
      console.warn("Failed to load pending donations:", error);
      this.pendingDonations = [];
    } finally {
      this.pendingDonationsLoaded = true;
    }
  }

  /**
   * Link the lottery to a pending donation
   */
  @action
  linkToDonation(donation) {
    this.donationId = donation.id;
    // Pre-fill title from donation if title is empty
    if (!this.title || this.title.trim() === "") {
      this.title = donation.title;
      if (this.formApi) {
        this.formApi.set("title", donation.title);
      }
      if (this._formData) {
        this._formData.title = donation.title;
      }
    }
    this._scheduleDraftSave();
  }

  /**
   * Check if there are pending donations to show the banner
   */
  get showPendingDonationsBanner() {
    return (
      this.pendingDonationsLoaded &&
      !this.donationId &&
      this.pendingDonations.length > 0
    );
  }

  /**
   * Load existing draft if available
   * Handles donation_id conflicts by asking user whether to discard
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
          const draftDonationId = draft.metaData.donation_id || null;
          const urlDonationId = this.donationId || null;

          // Check if there's a donation_id mismatch
          if (
            draftDonationId !== urlDonationId &&
            this._draftHasContent(draft)
          ) {
            // Ask user whether to discard the existing draft
            const confirmed = await this.dialog.confirm({
              title: i18n("vzekc_verlosung.draft_conflict.title"),
              message: i18n("vzekc_verlosung.draft_conflict.message"),
              confirmButtonLabel: i18n(
                "vzekc_verlosung.draft_conflict.discard"
              ),
              cancelButtonLabel: i18n("vzekc_verlosung.draft_conflict.keep"),
            });

            if (confirmed) {
              // User chose to discard - clear the draft and start fresh
              await Draft.clear("new_topic", result.draft_sequence);
              this.draftSequence = 0;
              return; // Don't load the draft content
            } else {
              // User chose to keep the draft - restore its donation_id
              this.donationId = draftDonationId;
              // Clear the URL donation title since we're using draft data
              // (title will be loaded from draft below)
            }
          }

          // Load draft content
          this.title = draft.title || "";
          // Ensure body is always a string
          this.body =
            typeof draft.reply === "string" && draft.reply
              ? draft.reply
              : this.template;
          this.durationDays = draft.metaData.lottery_duration_days || 14;
          this.drawingMode = draft.metaData.lottery_drawing_mode || "automatic";
          this.draftSequence = result.draft_sequence || 0;

          // Restore donation_id from draft if not set from URL
          if (!this.donationId && draftDonationId) {
            this.donationId = draftDonationId;
          }

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
        quantity: parseInt(packet.quantity, 10) || 1,
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
          donation_id: this.donationId,
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
      const errorMessage = extractError(error);
      this.dialog.alert(errorMessage);
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
          this.dialog.alert(
            i18n("vzekc_verlosung.errors.packet_title_required")
          );
          this.isSubmitting = false;
          return;
        }

        // Prepare packet data - include all packets with their ordinals
        // Abholerpaket always has quantity 1
        packets = this.packets.map((packet) => ({
          title: packet.title.trim(),
          raw: packet.raw.trim(),
          ordinal: packet.ordinal,
          quantity: packet.isAbholerpaket
            ? 1
            : parseInt(packet.quantity, 10) || 1,
          erhaltungsbericht_required: !packet.erhaltungsberichtNotRequired,
          is_abholerpaket: packet.isAbholerpaket || false,
        }));

        // Validate that at least one packet has content (title is required, raw is optional)
        if (packets.length === 0) {
          this.dialog.alert(
            i18n("vzekc_verlosung.errors.at_least_one_packet_required")
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

      // Mark as published to prevent willDestroy from re-saving draft
      this._publishedSuccessfully = true;

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
      // Extract and display the actual error message from AJAX response
      const errorMessage = extractError(error);
      this.dialog.alert(errorMessage);
    } finally {
      this.isSubmitting = false;
    }
  }

  <template>
    <div class="new-lottery-page">
      <div class="new-lottery-page__header">
        <h1>{{i18n "vzekc_verlosung.neue_verlosung"}}</h1>
      </div>

      {{#if this.showPendingDonationsBanner}}
        <div class="pending-donation-banner">
          <div class="pending-donation-banner__content">
            <span class="pending-donation-banner__icon">{{icon
                "circle-info"
              }}</span>
            <div class="pending-donation-banner__text">
              <strong>{{i18n
                  "vzekc_verlosung.pending_donation_banner.title"
                }}</strong>
              <p>{{i18n
                  "vzekc_verlosung.pending_donation_banner.description"
                }}</p>
            </div>
          </div>
          <div class="pending-donation-banner__donations">
            {{#each this.pendingDonations as |donation|}}
              <DButton
                @action={{fn this.linkToDonation donation}}
                @translatedLabel={{donation.title}}
                @icon="link"
                class="btn-primary"
              />
            {{/each}}
          </div>
        </div>
      {{/if}}

      {{#if this.donationId}}
        <div class="linked-donation-notice">
          {{icon "link"}}
          {{i18n "vzekc_verlosung.linked_donation_notice"}}
        </div>
      {{/if}}

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
                placeholder={{i18n
                  "vzekc_verlosung.composer.title_placeholder"
                }}
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
                    @content={{i18n
                      "vzekc_verlosung.composer.drawing_mode_hint"
                    }}
                  />
                </div>
                <field.Select
                  {{on "change" this.onFormFieldChange}}
                  as |select|
                >
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
            <div
              class="lottery-body-editor"
              {{didInsert this.setupBodyPasteHandler}}
              {{willDestroy this.cleanupBodyPasteHandler}}
            >
              <DEditor
                @value={{readonly field.value}}
                @change={{fn this.handleBodyFieldChange field.set}}
                @extraButtons={{this.extraButtons}}
                @onSetup={{this.onBodyEditorSetup}}
                class="form-kit__control-composer"
                style="height: 500px"
              />
              <PickFilesButton
                @registerFileInput={{this.registerBodyFileInput}}
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
                    <div class="packet-title-row">
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
                      {{#unless packet.isAbholerpaket}}
                        <div class="packet-quantity-input">
                          <label>{{i18n
                              "vzekc_verlosung.modal.packet_quantity_label"
                            }}</label>
                          <input
                            type="number"
                            min="1"
                            max="100"
                            value={{packet.quantity}}
                            {{on
                              "input"
                              (fn this.updatePacket index "quantity")
                            }}
                            class="packet-quantity-field"
                          />
                        </div>
                      {{/unless}}
                    </div>
                    <div
                      class="packet-editor"
                      {{didInsert (fn this.setupPacketPasteHandler index)}}
                      {{willDestroy (fn this.cleanupPacketPasteHandler index)}}
                    >
                      <DEditor
                        @value={{readonly packet.raw}}
                        @change={{fn this.updatePacketRaw index}}
                        @extraButtons={{this.packetExtraButtons index}}
                        @onSetup={{fn this.onPacketEditorSetup index}}
                        @preview={{false}}
                        @placeholder={{i18n
                          "vzekc_verlosung.modal.packet_description_placeholder"
                        }}
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
