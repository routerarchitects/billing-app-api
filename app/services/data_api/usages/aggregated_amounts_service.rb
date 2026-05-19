# frozen_string_literal: true

module DataApi
  module Usages
    class AggregatedAmountsService < DataApi::BaseService
      Result = BaseResult[:aggregated_amounts_usages]

      def call

        data_aggregated_amounts_usages = http_client.get(headers:, params:)

        result.aggregated_amounts_usages = data_aggregated_amounts_usages
        result
      end

      private

      def action_path
        "usages/#{organization.id}/aggregated_amounts/"
      end
    end
  end
end
