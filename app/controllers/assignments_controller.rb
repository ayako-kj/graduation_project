class AssignmentsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_assignment, only: %i[edit update destroy move_up move_down]

  def index
    @assignments = current_library.assignments.includes(:staffs).order(:sort_order, :id)
  end

  def new
    @assignment = current_library.assignments.build
    set_form_options
  end

  def create
    @assignment = current_library.assignments.build(assignment_params)
    @assignment.sort_order = current_library.assignments.maximum(:sort_order).to_i + 1
    if @assignment.save
      update_staffs(@assignment)
      redirect_to assignments_path, notice: "担当を登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @assignment.update(assignment_params)
      update_staffs(@assignment)
      redirect_to assignments_path, notice: "担当を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @assignment.destroy
    redirect_to assignments_path, notice: "#{@assignment.name}を削除しました。"
  end

  def move_up
    above = current_library.assignments.where("sort_order < ?", @assignment.sort_order).order(sort_order: :desc).first
    swap_sort_order(@assignment, above) if above
    redirect_to assignments_path
  end

  def move_down
    below = current_library.assignments.where("sort_order > ?", @assignment.sort_order).order(sort_order: :asc).first
    swap_sort_order(@assignment, below) if below
    redirect_to assignments_path
  end

  private

  def swap_sort_order(a, b)
    a_order = a.sort_order
    a.update_column(:sort_order, b.sort_order)
    b.update_column(:sort_order, a_order)
  end

  def set_assignment
    @assignment = current_library.assignments.find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
  end

  def update_staffs(assignment)
    ids = params.dig(:assignment, :staff_ids)&.reject(&:blank?)&.map(&:to_i) || []
    assignment.staffs = current_library.staffs.where(id: ids)
  end

  def assignment_params
    params.require(:assignment).permit(:name, :meeting_wday)
  end
end
