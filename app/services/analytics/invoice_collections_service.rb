# frozen_string_literal: true

module Analytics
  class InvoiceCollectionsService < BaseService
    def call

      @records = ::Analytics::InvoiceCollection.find_all_by(organization.id, **filters)

      result.records = records
      result
    end
  end
end
