# frozen_string_literal: true

module Integrations
  module Avalara
    class CreateService < Integrations::CreateService
      Result = BaseResult[:integration]

      def initialize(params:)
        @params = params

        super
      end

      def call
        organization = Organization.find_by(id: params[:organization_id])

        integration = Integrations::AvalaraIntegration.new(
          organization:,
          name: params[:name],
          code: params[:code],
          company_code: params[:company_code],
          connection_id: params[:connection_id],
          account_id: params[:account_id],
          license_key: params[:license_key]
        )

        integration.save!

        Integrations::Avalara::FetchCompanyIdJob.perform_later(integration:)

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end

      private

      attr_reader :params
    end
  end
end
