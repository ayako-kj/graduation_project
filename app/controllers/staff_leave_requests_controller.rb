class StaffLeaveRequestsController < ApplicationController
  before_action :authenticate_staff_token!

  LEAVE_TYPES = %w[公休 年休 夏期休暇].freeze

  def index
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a

    library = @current_staff.library
    holidays = HolidayFetcher.fetch(@target_month.year)
    extra = temporary_closed_dates_map(library, @target_month)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: library.closed_wdays_array, extra_closed_dates: extra).closed_days_with_labels

    @existing_leaves = LeaveRequest
      .where(staff: @current_staff, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |lr, h| h[lr.date] = lr.reason.presence || "公休" }
  end

  def save
    @target_month = parse_target_month
    leave_types = params[:leave_types]&.to_unsafe_h || {}
    selected_dates = Array(params[:leave_dates]).filter_map { |d| Date.parse(d) rescue nil }

    LeaveRequest.where(
      staff: @current_staff,
      date:  @target_month.beginning_of_month..@target_month.end_of_month
    ).destroy_all

    selected_dates.each do |date|
      leave_type = leave_types[date.to_s].presence
      leave_type = "公休" unless LEAVE_TYPES.include?(leave_type)
      LeaveRequest.create!(staff: @current_staff, date: date, reason: leave_type)
    end

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
