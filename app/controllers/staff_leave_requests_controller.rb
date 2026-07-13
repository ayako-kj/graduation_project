class StaffLeaveRequestsController < ApplicationController
  before_action :authenticate_staff_token!

  def index
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a

    holidays = HolidayFetcher.fetch(@target_month.year)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: @current_staff.library.closed_wdays_array).closed_days_with_labels

    @existing_leave_dates = LeaveRequest
      .where(staff: @current_staff, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .pluck(:date).to_set
  end

  def save
    @target_month = parse_target_month
    selected_dates = Array(params[:dates]).filter_map { |d| Date.parse(d) rescue nil }

    LeaveRequest.where(
      staff: @current_staff,
      date:  @target_month.beginning_of_month..@target_month.end_of_month
    ).destroy_all

    selected_dates.each { |date| LeaveRequest.create!(staff: @current_staff, date: date) }

    redirect_to staff_leave_input_path(token: params[:token], month: @target_month.strftime("%Y-%m")),
                notice: "#{@target_month.strftime('%Y年%-m月')}の希望休を保存しました。"
  end

  private

  def authenticate_staff_token!
    @current_staff = Staff.find_by(access_token: params[:token])
    return if @current_staff

    render plain: "アクセストークンが無効です。配布されたURLを確認してください。", status: :unauthorized
  end

  def parse_target_month
    Date.parse("#{params[:month]}-01")
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month
  end
end
