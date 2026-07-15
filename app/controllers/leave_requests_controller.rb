class LeaveRequestsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_leave_request, only: %i[edit update destroy]

  def index
    @target_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month
    @leave_requests = LeaveRequest.includes(:staff)
                        .where(staff: current_library.staffs)
                        .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                        .order(:date)
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
    @leave_request = LeaveRequest.where(staff: current_library.staffs).find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.order(:sort_order, :id)
  end

  def leave_request_params
    params.require(:leave_request).permit(:staff_id, :date, :reason)
  end
end
