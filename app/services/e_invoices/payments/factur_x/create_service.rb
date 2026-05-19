# frozen_string_literal: true

module EInvoices
  module Payments::FacturX
    class CreateService < ::BaseService
      def initialize(payment:)
        super

        @payment = payment
      end

      def call
        return result.not_found_failure!(resource: "payment") unless payment

        result.xml = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
          EInvoices::Payments::FacturX::Builder.serialize(xml:, payment:)
        end.to_xml

        result
      end

      private

      attr_accessor :payment
    end
  end
end
