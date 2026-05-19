# frozen_string_literal: true

require "lago_utils"

License = LagoUtils::License.new(Rails.application.config.license_url)
# OSS: do not verify license with any remote endpoint at boot time.
