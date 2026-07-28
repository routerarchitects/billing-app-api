# frozen_string_literal: true

require "rails_helper"

describe "Subscription Downgrade Scenario", transaction: false do
  let(:organization) { create(:organization, webhook_url: false) }

  let(:customer) { create(:customer, organization:) }

  let(:monthly_plan) do
    create(
      :plan,
      organization:,
      interval: "monthly",
      amount_cents: 12_900,
      pay_in_advance: true
    )
  end

  let(:yearly_plan) do
    create(
      :plan,
      organization:,
      interval: "yearly",
      amount_cents: 118_800,
      pay_in_advance: true
    )
  end

  let(:subscription_at) { DateTime.new(2023, 7, 19, 12, 12) }

  it "downgrades and bills subscriptions correctly" do
    yearly_subscription = nil

    # NOTE: July 19th 2023: Create the yearly subscription (starts active, billed in advance)
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

    # NOTE: November 9th 2023: Create a downgrade request (monthly plan), should be pending
    travel_to(DateTime.new(2023, 11, 9, 0, 0)) do
      create_subscription(
        {
          external_customer_id: customer.external_id,
          external_id: customer.external_id,
          plan_code: monthly_plan.code,
          billing_time: "anniversary"
        }
      )

      expect(yearly_subscription.reload).to be_active
      expect(yearly_subscription.next_subscription).to be_pending
      expect(yearly_subscription.invoices.count).to eq(1)
      expect(customer.invoices.count).to eq(1)
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

  context "when there are fixed charges" do
    let(:plan) { create(:plan, :monthly, pay_in_advance: false, amount_cents: 10000, organization:) }
    let(:plan_downgrade) { create(:plan, :monthly, pay_in_advance: false, amount_cents: 1000, organization:) }
    let(:add_ons) { create_list(:add_on, 3, organization:) }
    let(:fixed_charges_plan) {
      [
        create(:fixed_charge, plan:, add_on: add_ons[0], properties: {amount: "1"}, units: 10, pay_in_advance:, prorated:),
        create(:fixed_charge, plan:, add_on: add_ons[1], properties: {amount: "3"}, units: 5, pay_in_advance:, prorated:)
      ]
    }
    let(:fixed_charges_plan_downgrade) {
      [
        create(:fixed_charge, plan: plan_downgrade, add_on: add_ons[1], properties: {amount: "10"}, units: 10, pay_in_advance:, prorated:),
        create(:fixed_charge, plan: plan_downgrade, add_on: add_ons[2], properties: {amount: "20", units: 1}, pay_in_advance:, prorated:)
      ]
    }

    before do
      fixed_charges_plan
      fixed_charges_plan_downgrade
    end

    context "when fixed charges are in_advance" do
      let(:pay_in_advance) { true }

      context "when fixed charges are prorated" do
        let(:prorated) { true }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(1)
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000 * 13 / 31, 1500 * 13 / 31])

          travel_to(DateTime.new(2023, 8, 1, 0, 0)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_downgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 1, 0, 0)) do
            # we still need to charge subscription fee for the old plan
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(2).to(3)
          end

          # note: this invoice includes both subscriptions: old and new
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription, new_subscription])
          # this invoice contains subscription fee of the old plan
          expect(invoice.fees.subscription.count).to eq(1)
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          # and fixed_charges of the new plan
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end

      context "when fixed charges are not prorated" do
        let(:prorated) { false }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(1)
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])

          travel_to(DateTime.new(2023, 8, 1, 0, 0)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_downgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 1, 0, 0)) do
            # we still need to charge subscription fee for the old plan
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(2).to(3)
          end

          # note: this invoice includes both subscriptions: old and new
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription, new_subscription])
          # this invoice contains subscription fee of the old plan
          expect(invoice.fees.subscription.count).to eq(1)
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          # and fixed_charges of the new plan
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end
    end

    context "when fixed charges are in_arrears" do
      let(:pay_in_advance) { false }

      context "when fixed charges are prorated" do
        let(:prorated) { true }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(0)
          travel_to(DateTime.new(2023, 8, 1, 0, 0)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(0).to(1)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000 * 13 / 31, 1500 * 13 / 31])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-07-19T12:12:00.000Z",
            "fixed_charges_to_datetime" => "2023-07-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_downgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 1, 0, 0)) do
            # Now we do charge the old plan pay in arrears
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          # note: this invoice includes only old sub, because there is nothing to charge in the new one
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription])
          # this invoice contains subscription fee of the old plan
          # and pay in arrears fixed_charges
          expect(invoice.fees.subscription.count).to eq(1)
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          # why in this case do we have one more day? :shocked:
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          expect(new_subscription.invoices.count).to eq(0)

          travel_to(DateTime.new(2023, 10, 1, 0, 0)) do
            # finally charge the new plan (we're in arrears charges); prev invoice is counted for  both subscriptions
            expect { perform_billing }.to change { new_subscription.reload.invoices.count }.from(0).to(1)
          end
          invoice = new_subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end

      context "when fixed charges are not prorated" do
        let(:prorated) { false }

        it "calculates all fees" do
          # 2023, 7, 19, 12, 12
          travel_to(subscription_at) do
            create_subscription({
              external_customer_id: customer.external_id,
              external_id: customer.external_id,
              plan_code: plan.code,
              billing_time: "calendar"
            })
          end
          subscription = customer.subscriptions.first
          expect(subscription).to be_active
          expect(subscription.invoices.count).to eq(0)

          travel_to(DateTime.new(2023, 8, 1, 0, 0)) do
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(0).to(1)
          end

          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-07-19T12:12:00.000Z",
            "fixed_charges_to_datetime" => "2023-07-31T23:59:59.999Z"
          )

          travel_to(DateTime.new(2023, 8, 21, 23, 59, 59)) do
            create_subscription(
              {
                external_customer_id: customer.external_id,
                external_id: customer.external_id,
                plan_code: plan_downgrade.code,
                billing_time: "calendar"
              }
            )

            expect(subscription.reload).to be_active
          end
          new_subscription = subscription.reload.next_subscription

          travel_to(DateTime.new(2023, 9, 1, 0, 0)) do
            # Now we do charge the old plan
            expect { perform_billing }.to change { subscription.reload.invoices.count }.from(1).to(2)
          end

          # note: this invoice includes only old sub, because there is nothing to charge in the new one
          invoice = subscription.invoices.order(created_at: :asc).last
          expect(invoice.invoice_subscriptions.map(&:subscription)).to match_array([subscription])
          # this invoice contains subscription fee of the old plan
          expect(invoice.fees.subscription.count).to eq(1)
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([1000, 1500])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-08-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-08-31T23:59:59.999Z"
          )
          expect(subscription).to be_terminated

          expect(new_subscription.reload).to be_active
          expect(new_subscription.invoices.count).to eq(0)

          travel_to(DateTime.new(2023, 10, 1, 0, 0)) do
            # finally charge the new plan (we're in arrears charges); prev invoice is counted for  both subscriptions
            expect { perform_billing }.to change { new_subscription.reload.invoices.count }.from(0).to(1)
          end
          invoice = new_subscription.invoices.order(created_at: :asc).last
          expect(invoice.fees.fixed_charge.count).to eq(2)
          expect(invoice.fees.fixed_charge.map(&:amount_cents)).to match_array([10000, 2000])
          expect(invoice.fees.fixed_charge.sample.properties).to include(
            "fixed_charges_from_datetime" => "2023-09-01T00:00:00.000Z",
            "fixed_charges_to_datetime" => "2023-09-30T23:59:59.999Z"
          )
        end
      end
    end
  end
end
