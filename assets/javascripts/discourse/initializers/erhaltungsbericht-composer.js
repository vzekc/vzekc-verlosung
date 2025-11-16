import { apiInitializer } from "discourse/lib/api";

/**
 * Serializes reference fields from composer to topic opts
 * This allows Erhaltungsbericht creation to pass source references:
 * - packet_post_id and packet_topic_id for lottery packets (regular packets with posts)
 * - erhaltungsbericht_lottery_id and erhaltungsbericht_is_abholerpaket for Abholerpakete (no posts)
 * - erhaltungsbericht_donation_id for donations
 */
export default apiInitializer((api) => {
  // Add fields to draft serializer so they are set on the composer model from opts
  api.serializeToDraft("packet_post_id", "vzekc_packet_post_id");
  api.serializeToDraft("packet_topic_id", "vzekc_packet_topic_id");
  api.serializeToDraft(
    "erhaltungsbericht_lottery_id",
    "vzekc_erhaltungsbericht_lottery_id"
  );
  api.serializeToDraft(
    "erhaltungsbericht_is_abholerpaket",
    "vzekc_erhaltungsbericht_is_abholerpaket"
  );
  api.serializeToDraft(
    "erhaltungsbericht_donation_id",
    "vzekc_erhaltungsbericht_donation_id"
  );

  // Add fields to create serializer so they are sent in the POST request
  api.serializeOnCreate("packet_post_id", "vzekc_packet_post_id");
  api.serializeOnCreate("packet_topic_id", "vzekc_packet_topic_id");
  api.serializeOnCreate(
    "erhaltungsbericht_lottery_id",
    "vzekc_erhaltungsbericht_lottery_id"
  );
  api.serializeOnCreate(
    "erhaltungsbericht_is_abholerpaket",
    "vzekc_erhaltungsbericht_is_abholerpaket"
  );
  api.serializeOnCreate(
    "erhaltungsbericht_donation_id",
    "vzekc_erhaltungsbericht_donation_id"
  );
});
