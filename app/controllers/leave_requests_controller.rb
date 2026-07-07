class LeaveRequestsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_leave_request, only: %i[edit update destroy]

  def index
    @leave_requests = LeaveRequest.includes(:staff).order(:date)
  end

  def new
    @leave_request = LeaveRequest.new
    set_form_options
  end

  def create
    @leave_request = LeaveRequest.new(leave_request_params)
    if @leave_request.save
      redirect_to leave_requests_path, notice: "希望休を登録しました。"
    else
      set_form_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    set_form_options
  end

  def update
    if @leave_request.update(leave_request_params)
      redirect_to leave_requests_path, notice: "希望休を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @leave_request.destroy
    redirect_to leave_requests_path, notice: "希望休を削除しました。"
  end

  private

  def set_leave_request
    @leave_request = LeaveRequest.find(params[:id])
  end

  def set_form_options
    @staffs = Staff.order(:name)
  end

  def leave_request_params
    params.require(:leave_request).permit(:staff_id, :date, :reason)
  end
end
