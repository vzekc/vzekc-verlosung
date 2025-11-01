import { apiInitializer } from "discourse/lib/api";

/**
 * Fix for Discourse core PostFilteredNotice/PostMetaDataPosterName component crash
 * when post data is undefined.
 *
 * This happens when viewing a topic with username filters but not enough posts in the stream,
 * or when post data hasn't loaded yet.
 */
export default apiInitializer((api) => {
  // Add defensive check to PostMetaDataPosterName to handle undefined posts
  api.modifyClass("component:post/meta-data/poster-name", {
    pluginId: "vzekc-verlosung",

    /**
     * Override user getter to safely handle undefined post
     *
     * @returns {Object|undefined} the post user or undefined
     */
    get user() {
      return this.args.post?.user;
    },

    /**
     * Override shouldShow to handle undefined user
     *
     * @returns {Boolean} whether to show the component
     */
    get shouldShow() {
      return !!this.user;
    },
  });

  // Add defensive checks to PostFilteredNotice
  api.modifyClass("component:post/filtered-notice", {
    pluginId: "vzekc-verlosung",

    /**
     * Override firstUserPost to add defensive check
     *
     * @returns {Object|undefined} the first user post or undefined
     */
    get firstUserPost() {
      return this.args.posts?.[1];
    },

    /**
     * Override sourcePost to add defensive check
     *
     * @returns {Object|undefined} the source post or undefined
     */
    get sourcePost() {
      if (!this.args.posts) {
        return undefined;
      }
      return this.args.posts.find(
        (post) =>
          post?.post_number === this.args.streamFilters?.replies_to_post_number
      );
    },
  });
});
