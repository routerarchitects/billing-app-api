# frozen_string_literal: true

module Integrations
  module Salesforce
    class CreateService < Integrations::CreateService
      attr_reader :params

      def initialize(params:)
        @params = params

        super
      end

      def call
        organization = Organization.find_by(id: params[:organization_id])

        integration = Integrations::SalesforceIntegration.new(
          organization:,
          name: params[:name],
          code: params[:code],
          instance_id: params[:instance_id]
        )

        integration.save!

        result.integration = integration
        result
      rescue ActiveRecord::RecordInvalid => e
        result.record_validation_failure!(record: e.record)
      end
    end
  end
end
