class StaffTypesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_staff_type, only: %i[destroy move_up move_down]

  def index
    @staff_types = StaffType.order(:sort_order, :id)
    @staff_type = StaffType.new
    @employment_types = EmploymentType.order(:id)
    @employment_type = EmploymentType.new
  end

  def create
    @staff_type = StaffType.new(staff_type_params)
    @staff_type.sort_order = (StaffType.maximum(:sort_order) || 0) + 1
    if @staff_type.save
      redirect_to staff_types_path, notice: "職種「#{@staff_type.name}」を追加しました。"
    else
      @staff_types = StaffType.order(:sort_order, :id)
      @employment_types = EmploymentType.order(:id)
      @employment_type = EmploymentType.new
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    if @staff_type.destroy
      redirect_to staff_types_path, notice: "職種「#{@staff_type.name}」を削除しました。"
    else
      redirect_to staff_types_path, alert: "#{@staff_type.name}は職員に使用中のため削除できません。"
    end
  end

  def move_up
    swap_sort_order(@staff_type, :up)
    redirect_to staff_types_path
  end

  def move_down
    swap_sort_order(@staff_type, :down)
    redirect_to staff_types_path
  end

  private

  def set_staff_type
    @staff_type = StaffType.find(params[:id])
  end

  def staff_type_params
    params.require(:staff_type).permit(:name)
  end

  def swap_sort_order(staff_type, direction)
    ordered = StaffType.order(:sort_order, :id).to_a
    idx = ordered.index(staff_type)
    return unless idx

    other_idx = direction == :up ? idx - 1 : idx + 1
    return unless other_idx.between?(0, ordered.size - 1)

    other = ordered[other_idx]
    a, b = staff_type.sort_order, other.sort_order
    staff_type.update_column(:sort_order, b)
    other.update_column(:sort_order, a)
  end
end
