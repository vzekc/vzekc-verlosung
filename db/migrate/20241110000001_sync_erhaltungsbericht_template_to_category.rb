# frozen_string_literal: true

# Migration to sync the erhaltungsbericht template from site settings to the category's topic_template
# This ensures existing installations have the template set on the category for manual topic creation
class SyncErhaltungsberichtTemplateToCategory < ActiveRecord::Migration[7.1]
  def up
    # Get the erhaltungsberichte category ID from site settings
    category_id =
      DB
        .query_single(
          "SELECT value FROM site_settings WHERE name = 'vzekc_verlosung_erhaltungsberichte_category_id'",
        )
        .first
        &.to_i

    return if category_id.blank? || category_id.zero?

    # Get the erhaltungsbericht template from site settings
    template =
      DB.query_single(
        "SELECT value FROM site_settings WHERE name = 'vzekc_verlosung_erhaltungsbericht_template'",
      ).first

    return if template.blank?

    # Update the category's topic_template
    DB.exec("UPDATE categories SET topic_template = ? WHERE id = ?", template, category_id)

    Rails.logger.info(
      "Synced erhaltungsbericht template to category #{category_id} during migration",
    )
  end

  def down
    # No rollback needed - we don't want to clear the template
    # The template will continue to work even if the migration is rolled back
  end
end
