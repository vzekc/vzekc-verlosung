import { next } from "@ember/runloop";
import { apiInitializer } from "discourse/lib/api";
import { i18n } from "discourse-i18n";

// Markdown images (uploads and external URLs) and inline <img> tags
const IMAGE_PATTERN = /!\[[^\]]*\]\([^)]+\)|<img\b/i;

/**
 * Asks the author of a new Erhaltungsbericht without a picture to add one
 * before posting. The author can post without a picture after all.
 */
export default apiInitializer((api) => {
  api.modifyClass(
    "service:composer",
    (Superclass) =>
      class extends Superclass {
        /**
         * Asks for a picture before saving a new Erhaltungsbericht without
         * one. Saving while an upload is in progress goes straight to core,
         * which refuses it.
         *
         * @param {boolean} force
         * @param {Object} options
         */
        save(force, options = {}) {
          if (
            this.disableSubmit ||
            options.vzekcImageCheckDone ||
            !this.vzekcErhaltungsberichtLacksImage()
          ) {
            return super.save(force, options);
          }

          this.dialog.alert({
            title: i18n("vzekc_verlosung.erhaltungsbericht.image_check.title"),
            message: i18n(
              "vzekc_verlosung.erhaltungsbericht.image_check.message"
            ),
            buttons: [
              {
                label: i18n(
                  "vzekc_verlosung.erhaltungsbericht.image_check.add_image"
                ),
                icon: "image",
                class: "btn-primary",
                action: () => document.getElementById("file-uploader")?.click(),
              },
              {
                label: i18n(
                  "vzekc_verlosung.erhaltungsbericht.image_check.post_anyway"
                ),
                class: "btn-default",
                // The dialog closes after this action returns; saving on the
                // next run loop keeps any dialog the save opens visible.
                action: () =>
                  next(() =>
                    this.save(force, { ...options, vzekcImageCheckDone: true })
                  ),
              },
            ],
          });
        }

        /**
         * @returns {boolean} true for a new, otherwise postable topic in the
         *   Erhaltungsberichte category whose text contains no image
         */
        vzekcErhaltungsberichtLacksImage() {
          const model = this.model;
          const categoryId = parseInt(
            this.siteSettings.vzekc_verlosung_erhaltungsberichte_category_id,
            10
          );

          return (
            !!categoryId &&
            model?.creatingTopic &&
            !model.cantSubmitPost &&
            model.categoryId === categoryId &&
            !IMAGE_PATTERN.test(model.reply || "")
          );
        }
      }
  );
});
