class StaffsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_staff, only: %i[edit update destroy move_up move_down]

  def index
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)
  end

  def new
    @staff = current_library.staffs.build
    set_form_options
  end

  def create
    @staff = current_library.staffs.build(staff_params)
    @staff.sort_order = current_library.staffs.maximum(:sort_order).to_i + 1
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

  def move_up
    above = current_library.staffs.where("sort_order < ?", @staff.sort_order).order(sort_order: :desc).first
    swap_sort_order(@staff, above) if above
    redirect_to staffs_path
  end

  def move_down
    below = current_library.staffs.where("sort_order > ?", @staff.sort_order).order(sort_order: :asc).first
    swap_sort_order(@staff, below) if below
    redirect_to staffs_path
  end

  private

  def swap_sort_order(a, b)
    a_order = a.sort_order
    a.update_column(:sort_order, b.sort_order)
    b.update_column(:sort_order, a_order)
  end

  def set_staff
    @staff = current_library.staffs.find(params[:id])
  end

  def set_form_options
    @staff_types = StaffType.order(:sort_order, :id)
    @employment_types = EmploymentType.all
  end

  def staff_params
    params.require(:staff).permit(:name, :staff_type_id, :employment_type_id, :weekly_work_days)
  end
end
