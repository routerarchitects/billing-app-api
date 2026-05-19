# frozen_string_literal: true

module DataApi
  module Usages
    class InvoicedService < DataApi::BaseService
      Result = BaseResult[:invoiced_usages]

      def call

        data_invoiced_usages = http_client.get(headers:, params:)

        result.invoiced_usages = data_invoiced_usages
        result
      end

      private

      def action_path
        "usages/#{organization.id}/invoiced/"
      end
    end
  end
end
