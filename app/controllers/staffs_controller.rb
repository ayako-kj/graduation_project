class StaffsController < ApplicationController
  before_action :authenticate_admin!

  def index
    @staffs = Staff.includes(:staff_type, :employment_type).order(:id)
  end

  def new
    @staff = Staff.new
    @staff_types = StaffType.all
    @employment_types = EmploymentType.all
  end

  def create
    @staff = Staff.new(staff_params)
    if @staff.save
      redirect_to staffs_path, notice: "職員を登録しました。"
    else
      @staff_types = StaffType.all
      @employment_types = EmploymentType.all
      render :new, status: :unprocessable_entity
    end
  end

  private

  def staff_params
    params.require(:staff).permit(:name, :staff_type_id, :employment_type_id, :weekly_work_days)
  end
end
