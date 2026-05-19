# frozen_string_literal: true

module DataApi
  module Usages
    class ForecastedService < DataApi::BaseService
      Result = BaseResult[:forecasted_usages]

      def call

        data_forecasted_usages = http_client.get(headers:, params:)
        result.forecasted_usages = data_forecasted_usages
        result
      rescue Socket::ResolutionError, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
        Rails.logger.warn(
          "[DataApi::Usages::ForecastedService] data-api unavailable (#{e.class}): #{e.message}"
        )
        # If the optional data-api service isn't running, compute a local, best-effort forecast
        # from Lago's own invoiced-usage analytics so UI graphs still work.
        result.forecasted_usages = fallback_forecasted_usages
        result
      end

      private

      def action_path
        "usages/#{organization.id}/forecasted/"
      end

      def fallback_forecasted_usages
        require "date"

        currency = (params[:currency].presence || organization.default_currency || "USD").to_s.upcase

        from_date = params[:from_date].presence && Date.parse(params[:from_date].to_s)
        to_date = params[:to_date].presence && Date.parse(params[:to_date].to_s)

        # Lago UI defaults to a 12-month monthly window. Keep that behavior server-side too
        # so the query works even when the client doesn't pass date filters.
        from_date ||= Date.current.beginning_of_month
        to_date ||= (from_date >> 11).end_of_month

        # Only support monthly for now; if the UI requests other granularities, fall back to monthly.
        period_start = from_date.beginning_of_month
        period_end = to_date.end_of_month

        months = []
        cursor = period_start
        while cursor <= period_end
          months << cursor
          cursor = cursor >> 1
        end

        # Pull historical monthly invoiced usage amounts (per billable metric) and aggregate by month.
        # This uses Lago's own DB, not data-api.
        historical = ::Analytics::InvoicedUsage.find_all_by(
          organization.id,
          currency: currency,
          months: 24
        )

        amount_by_month = Hash.new(0)
        historical.each do |row|
          month_key =
            if row.respond_to?(:month)
              row.month.to_date.beginning_of_month
            else
              Date.parse(row["month"].to_s).beginning_of_month
            end

          amount_cents =
            if row.respond_to?(:amount_cents)
              row.amount_cents.to_i
            else
              row["amount_cents"].to_i
            end

          amount_by_month[month_key] += amount_cents
        end

        # Simple projection: average of last 3 available months, with +/- 10% bands.
        last_months = amount_by_month.keys.sort.last(3)
        avg =
          if last_months.any?
            last_months.sum { |m| amount_by_month[m] }.fdiv(last_months.size)
          else
            0.0
          end

        conservative = (avg * 0.9).round
        realistic = avg.round
        optimistic = (avg * 1.1).round

        months.map do |month_start|
          month_end = month_start.end_of_month
          actual_amount = amount_by_month[month_start] || 0

          {
            amount_cents: actual_amount,
            amount_cents_forecast_conservative: conservative,
            amount_cents_forecast_realistic: realistic,
            amount_cents_forecast_optimistic: optimistic,
            amount_currency: currency,
            units: 0.0,
            units_forecast_conservative: 0.0,
            units_forecast_realistic: 0.0,
            units_forecast_optimistic: 0.0,
            start_of_period_dt: month_start,
            end_of_period_dt: month_end
          }
        end
      rescue => e
        Rails.logger.warn(
          "[DataApi::Usages::ForecastedService] local forecast fallback failed (#{e.class}): #{e.message}"
        )
        []
      end
    end
  end
end
