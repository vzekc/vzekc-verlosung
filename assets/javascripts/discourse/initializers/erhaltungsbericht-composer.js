import { apiInitializer } from "discourse/lib/api";

/**
 * Serializes packet reference fields from composer to topic opts
 * This allows the Erhaltungsbericht creation flow to pass packet_post_id
 * and packet_topic_id to the topic_created callback
 */
export default apiInitializer((api) => {
  // Add fields to draft serializer so they are set on the composer model from opts
  api.serializeToDraft("packet_post_id", "vzekc_packet_post_id");
  api.serializeToDraft("packet_topic_id", "vzekc_packet_topic_id");

  // Add fields to create serializer so they are sent in the POST request
  api.serializeOnCreate("packet_post_id", "vzekc_packet_post_id");
  api.serializeOnCreate("packet_topic_id", "vzekc_packet_topic_id");
});
