# frozen_string_literal: true

module DataApi
  class UsagesService < DataApi::BaseService
    Result = BaseResult[:usages]

    def call
      response = http_client.get(headers:, params: filtered_params)

      result.usages = response.map do |usage|
        code = usage["billable_metric_code"]
        usage["is_billable_metric_deleted"] = discarded_billable_metrics_codes.include?(code)
        usage
      end

      result
    end

    private

    def discarded_billable_metrics_codes
      @discarded_billable_metrics_codes ||= BillableMetric.where(organization:).with_discarded.discarded.pluck(:code)
    end

    def filtered_params
      params.dup.tap do |filtered|
        filtered[:time_granularity] ||= "daily"
      end
    end

    def action_path
      "usages/#{organization.id}/"
    end
  end
end
