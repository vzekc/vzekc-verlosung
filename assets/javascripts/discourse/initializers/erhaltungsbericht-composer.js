import { apiInitializer } from "discourse/lib/api";

/**
 * Serializes packet reference fields from composer to topic custom fields
 * This allows the Erhaltungsbericht creation flow to pass packet_post_id
 * and packet_topic_id through the composer to the created topic
 */
export default apiInitializer((api) => {
  // Serialize vzekc_packet_post_id from composer to topic custom field
  api.serializeToTopic("packet_post_id", "composer.vzekc_packet_post_id");

  // Serialize vzekc_packet_topic_id from composer to topic custom field
  api.serializeToTopic("packet_topic_id", "composer.vzekc_packet_topic_id");
});
