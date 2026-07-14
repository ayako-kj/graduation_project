class EmploymentTypesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_employment_type, only: %i[destroy]

  def create
    @employment_type = EmploymentType.new(employment_type_params)
    if @employment_type.save
      redirect_to staff_types_path, notice: "雇用形態「#{@employment_type.name}」を追加しました。"
    else
      @staff_types = StaffType.order(:sort_order, :id)
      @staff_type = StaffType.new
      @employment_types = EmploymentType.order(:id)
      render "staff_types/index", status: :unprocessable_entity
    end
  end

  def destroy
    if @employment_type.destroy
      redirect_to staff_types_path, notice: "雇用形態「#{@employment_type.name}」を削除しました。"
    else
      redirect_to staff_types_path, alert: "#{@employment_type.name}は職員に使用中のため削除できません。"
    end
  end

  private

  def set_employment_type
    @employment_type = EmploymentType.find(params[:id])
  end

  def employment_type_params
    params.require(:employment_type).permit(:name)
  end
end
