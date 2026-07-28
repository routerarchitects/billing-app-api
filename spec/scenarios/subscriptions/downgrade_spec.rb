# frozen_string_literal: true

require "rails_helper"

describe "Subscription Downgrade Scenario", transaction: false do
  let(:organization) { create(:organization, webhook_url: false) }

  let(:customer) { create(:customer, organization:) }

  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 118_800,
      pay_in_advance: true
    )
  end

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 12_900,
      pay_in_advance: true
    )
  end

  let(:subscription_at) { DateTime.new(2023, 7, 19, 12, 12) }

  it "downgrades and bills subscriptions correctly" do
    yearly_subscription = nil

    # NOTE: Jul 19th 2023: create the yearly subscription
    travel_to(subscription_at) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: yearly_plan.code,
          billing_time: "anniversary",
          subscription_at: subscription_at.iso8601
        }
      )

      yearly_subscription = customer.subscriptions.first
      expect(yearly_subscription).to be_active
      expect(yearly_subscription.invoices.count).to eq(1)

      invoice = yearly_subscription.invoices.last
      expect(invoice.fees_amount_cents).to eq(yearly_plan.amount_cents)
      expect(invoice.invoice_subscriptions.first.from_datetime.iso8601).to eq("2023-07-19T00:00:00Z")
      expect(invoice.invoice_subscriptions.first.to_datetime.iso8601).to eq("2024-07-18T23:59:59Z")
    end

    # NOTE: November 9th 2023: Downgrade to the monthly plan (should remain pending)
    travel_to(DateTime.new(2023, 11, 9, 12, 12)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary"
        }
      )

      expect(yearly_subscription.reload).to be_active

      pending_subscription = customer.subscriptions.find_by(status: :pending)
      expect(pending_subscription).not_to be_nil
      expect(pending_subscription.plan.code).to eq(monthly_plan.code)
      expect(pending_subscription.previous_subscription).to eq(yearly_subscription)
    end

    # NOTE: July 19th 2024: End of yearly billing period, monthly subscription becomes active
    travel_to(DateTime.new(2024, 7, 19, 12, 12)) do
      expect { perform_billing }.to change { customer.subscriptions.find_by(status: :pending) }.to(nil)

      expect(yearly_subscription.reload).to be_terminated

      monthly_subscription = customer.subscriptions.order(created_at: :asc).last
      expect(monthly_subscription).to be_active
      expect(monthly_subscription.plan.code).to eq(monthly_plan.code)
      expect(monthly_subscription.invoices.count).to eq(1)

      invoice = monthly_subscription.invoices.last
      expect(invoice.fees_amount_cents).to eq(monthly_plan.amount_cents)

      invoice_sub = invoice.invoice_subscriptions.find_by(subscription: monthly_subscription)
      expect(invoice_sub.from_datetime.iso8601).to eq("2024-07-19T00:00:00Z")
      expect(invoice_sub.to_datetime.iso8601).to eq("2024-08-18T23:59:59Z")
    end
  end
end
