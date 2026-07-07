class PlacementRulesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_placement_rule, only: %i[edit update]

  def index
    @placement_rules = PlacementRule.includes(:staff_type).order(:id)
  end

  def new
    @placement_rule = PlacementRule.new
    set_form_options
  end

  def create
    @placement_rule = PlacementRule.new(placement_rule_params)
    if @placement_rule.save
      redirect_to placement_rules_path, notice: "配置ルールを登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @placement_rule.update(placement_rule_params)
      redirect_to placement_rules_path, notice: "配置ルールを更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_placement_rule
    @placement_rule = PlacementRule.find(params[:id])
  end

  def set_form_options
    @staff_types = StaffType.all
  end

  def placement_rule_params
    params.require(:placement_rule).permit(:staff_type_id, :min_count)
  end
end
