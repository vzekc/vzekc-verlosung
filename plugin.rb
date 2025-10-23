# frozen_string_literal: true

# name: vzekc-verlosung
# about: TODO
# meta_topic_id: TODO
# version: 0.0.1
# authors: Discourse
# url: TODO
# required_version: 2.7.0

enabled_site_setting :vzekc_verlosung_enabled

module ::VzekcVerlosung
  PLUGIN_NAME = "vzekc-verlosung"
end

require_relative "lib/vzekc_verlosung/engine"

after_initialize do
  # Code which should run after Rails has finished booting
end
