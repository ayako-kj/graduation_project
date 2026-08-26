class AssignmentsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_assignment, only: %i[edit update destroy]

  def index
    @assignments = current_library.assignments.includes(:staffs).order(:id)
  end

  def new
    @assignment = current_library.assignments.build
    set_form_options
  end

  def create
    @assignment = current_library.assignments.build(assignment_params)
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

  private

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
