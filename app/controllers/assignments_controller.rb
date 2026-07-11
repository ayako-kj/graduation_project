class AssignmentsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_assignment, only: %i[edit update destroy]

  def index
    @assignments = current_library.assignments.includes(:staffs).order(:id)
  end

  def new
    @assignment = current_library.assignments.build
  end

  def create
    @assignment = current_library.assignments.build(assignment_params)
    if @assignment.save
      redirect_to assignments_path, notice: "担当を登録しました。"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @assignment.update(assignment_params)
      redirect_to assignments_path, notice: "担当を更新しました。"
    else
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

  def assignment_params
    params.require(:assignment).permit(:name, :meeting_wday)
  end
end
