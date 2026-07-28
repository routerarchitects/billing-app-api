# frozen_string_literal: true

require "rails_helper"

RSpec.describe Plans::ChangeClassificationService do
  subject(:service) { described_class.new(current_plan:, target_plan:) }

  let(:organization) { create(:organization) }
  let(:current_plan) { create(:plan, organization:, interval: current_interval, amount_cents: current_amount) }
  let(:target_plan) { create(:plan, organization:, interval: target_interval, amount_cents: target_amount) }
  let(:current_interval) { "monthly" }
  let(:target_interval) { "monthly" }
  let(:current_amount) { 100 }
  let(:target_amount) { 100 }

  describe "#call" do
    describe "interval transitions" do
      [
        # Upgrade transitions
        {from: "weekly", to: "monthly", expected: :upgrade},
        {from: "monthly", to: "quarterly", expected: :upgrade},
        {from: "quarterly", to: "semiannual", expected: :upgrade},
        {from: "semiannual", to: "yearly", expected: :upgrade},

        # Downgrade transitions
        {from: "monthly", to: "weekly", expected: :downgrade},
        {from: "quarterly", to: "monthly", expected: :downgrade},
        {from: "semiannual", to: "quarterly", expected: :downgrade},
        {from: "yearly", to: "semiannual", expected: :downgrade}
      ].each do |scenario|
        it "classifies #{scenario[:from]} -> #{scenario[:to]} as #{scenario[:expected]}" do
          current_p = create(:plan, organization:, interval: scenario[:from])
          target_p = create(:plan, organization:, interval: scenario[:to])

          result = described_class.new(current_plan: current_p, target_plan: target_p).call
          expect(result.classification).to eq(scenario[:expected])
        end
      end
    end

    describe "same interval price transitions" do
      let(:current_interval) { "monthly" }
      let(:target_interval) { "monthly" }

      context "when target price is higher" do
        let(:current_amount) { 100 } # yearly_amount_cents = 1200
        let(:target_amount) { 150 }  # yearly_amount_cents = 1800

        it "classifies as upgrade" do
          expect(service.call.classification).to eq(:upgrade)
        end
      end

      context "when target price is equal" do
        let(:current_amount) { 100 }
        let(:target_amount) { 100 }

        it "classifies as upgrade" do
          expect(service.call.classification).to eq(:upgrade)
        end
      end

      context "when target price is lower" do
        let(:current_amount) { 100 }
        let(:target_amount) { 50 } # yearly_amount_cents = 600

        it "classifies as downgrade" do
          expect(service.call.classification).to eq(:downgrade)
        end
      end
    end

    describe "unsupported intervals" do
      context "when current plan has unsupported interval" do
        let(:current_p) { create(:plan, organization:) }

        it "raises a KeyError" do
          allow(current_p).to receive(:interval).and_return("biweekly")
          expect {
            described_class.new(current_plan: current_p, target_plan: target_plan).call
          }.to raise_error(KeyError)
        end
      end

      context "when target plan has unsupported interval" do
        let(:target_p) { create(:plan, organization:) }

        it "raises a KeyError" do
          allow(target_p).to receive(:interval).and_return("biweekly")
          expect {
            described_class.new(current_plan: current_plan, target_plan: target_p).call
          }.to raise_error(KeyError)
        end
      end
    end
  end
end
