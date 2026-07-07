class PlacementRulesController < ApplicationController
  before_action :authenticate_admin!

  def new
    @placement_rule = PlacementRule.new
    @staff_types = StaffType.all
  end

  def create
    @placement_rule = PlacementRule.new(placement_rule_params)
    if @placement_rule.save
      redirect_to new_placement_rule_path, notice: "配置ルールを登録しました。"
    else
      @staff_types = StaffType.all
      render :new, status: :unprocessable_entity
    end
  end

  private

  def placement_rule_params
    params.require(:placement_rule).permit(:staff_type_id, :min_count)
  end
end
