# frozen_string_literal: true

module Clock
  class ProcessAllSubscriptionActivitiesJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform

      UsageMonitoring::ProcessAllSubscriptionActivitiesService.call!
    end
  end
end
