# frozen_string_literal: true

module Plans
  class ChangeClassificationService < BaseService
    Result = BaseResult[:classification]

    def initialize(current_plan:, target_plan:)
      super()
      @current_plan = current_plan
      @target_plan = target_plan
    end

    def call
      interval_weights = {"weekly" => 1, "monthly" => 2, "quarterly" => 3, "semiannual" => 4, "yearly" => 5}
      current_weight = interval_weights.fetch(current_plan.interval.to_s)
      target_weight = interval_weights.fetch(target_plan.interval.to_s)

      result.classification = if target_weight > current_weight
        :upgrade
      elsif target_weight < current_weight
        :downgrade
      elsif target_plan.yearly_amount_cents >= current_plan.yearly_amount_cents
        :upgrade
      else
        :downgrade
      end

      result
    end

    private

    attr_reader :current_plan, :target_plan
  end
end
