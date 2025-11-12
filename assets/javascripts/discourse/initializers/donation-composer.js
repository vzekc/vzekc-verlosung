import { apiInitializer } from "discourse/lib/api";

/**
 * Serializes donation_id from composer to topic opts
 * This allows passing donation_id to the topic_created callback
 */
export default apiInitializer((api) => {
  // Add field to draft serializer so it is set on the composer model from opts
  api.serializeToDraft("donation_id", "vzekc_donation_id");

  // Add field to create serializer so it is sent in the POST request
  api.serializeOnCreate("donation_id", "vzekc_donation_id");
});
