import { apiInitializer } from "discourse/lib/api";

/**
 * Serializes reference fields from composer to topic opts
 * This allows Erhaltungsbericht creation to pass source references:
 * - packet_post_id and packet_topic_id for lottery packets (all packets including Abholerpaket)
 * - winner_instance_number for multi-instance packets
 * - erhaltungsbericht_donation_id for donations
 */
export default apiInitializer((api) => {
  // Add fields to draft serializer so they are set on the composer model from opts
  api.serializeToDraft("packet_post_id", "vzekc_packet_post_id");
  api.serializeToDraft("packet_topic_id", "vzekc_packet_topic_id");
  api.serializeToDraft(
    "winner_instance_number",
    "vzekc_winner_instance_number"
  );
  api.serializeToDraft(
    "erhaltungsbericht_donation_id",
    "vzekc_erhaltungsbericht_donation_id"
  );

  // Add fields to create serializer so they are sent in the POST request
  api.serializeOnCreate("packet_post_id", "vzekc_packet_post_id");
  api.serializeOnCreate("packet_topic_id", "vzekc_packet_topic_id");
  api.serializeOnCreate(
    "winner_instance_number",
    "vzekc_winner_instance_number"
  );
  api.serializeOnCreate(
    "erhaltungsbericht_donation_id",
    "vzekc_erhaltungsbericht_donation_id"
  );
});
