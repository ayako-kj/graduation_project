class PlacementRulesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_placement_rule, only: %i[edit update destroy]

  def index
    @placement_rules = current_library.placement_rules
                                      .includes(:staff_type, :employment_type)
                                      .order(:id)
  end

  def new
    @placement_rule = current_library.placement_rules.build(rule_type: "min_count")
    set_form_options
  end

  def create
    @placement_rule = current_library.placement_rules.build(placement_rule_params)
    normalize_staff_type_ids
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
    @placement_rule.assign_attributes(placement_rule_params)
    normalize_staff_type_ids
    if @placement_rule.save
      redirect_to placement_rules_path, notice: "配置ルールを更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @placement_rule.destroy
    redirect_to placement_rules_path, notice: "配置ルールを削除しました。"
  end

  private

  def set_placement_rule
    @placement_rule = current_library.placement_rules.find(params[:id])
  end

  def set_form_options
    @staff_types = StaffType.order(:sort_order, :id)
    @employment_types = EmploymentType.all
  end

  def normalize_staff_type_ids
    ids = params.dig(:placement_rule, :staff_type_ids_array)
    if ids.present?
      @placement_rule.staff_type_ids = ids.reject(&:blank?).to_json
    else
      @placement_rule.staff_type_ids = nil
    end
  end

  def placement_rule_params
    params.require(:placement_rule).permit(
      :rule_type, :staff_type_id, :employment_type_id, :min_count
    )
  end
end
