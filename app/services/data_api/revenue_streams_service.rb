# frozen_string_literal: true

module DataApi
  class RevenueStreamsService < BaseService
    Result = BaseResult[:revenue_streams]

    def call

      data_revenue_streams = http_client.get(headers:, params:)

      result.revenue_streams = data_revenue_streams
      result
    end

    private

    def action_path
      "revenue_streams/#{organization.id}/"
    end
  end
end
