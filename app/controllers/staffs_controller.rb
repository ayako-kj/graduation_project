class StaffsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_staff, only: %i[edit update destroy]

  def index
    @staffs = Staff.includes(:staff_type, :employment_type).order(:id)
  end

  def new
    @staff = Staff.new
    set_form_options
  end

  def create
    @staff = Staff.new(staff_params)
    if @staff.save
      redirect_to staffs_path, notice: "職員を登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @staff.update(staff_params)
      redirect_to staffs_path, notice: "職員情報を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @staff.destroy
    redirect_to staffs_path, notice: "#{@staff.name}を削除しました。"
  end

  private

  def set_staff
    @staff = Staff.find(params[:id])
  end

  def set_form_options
    @staff_types = StaffType.all
    @employment_types = EmploymentType.all
  end

  def staff_params
    params.require(:staff).permit(:name, :staff_type_id, :employment_type_id, :weekly_work_days)
  end
end
