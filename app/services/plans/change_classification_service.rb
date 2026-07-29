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
      current_weight = Plan::INTERVAL_WEIGHTS.fetch(current_plan.interval.to_s)
      target_weight = Plan::INTERVAL_WEIGHTS.fetch(target_plan.interval.to_s)

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
