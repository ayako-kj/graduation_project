class StaffLeaveRequestsController < ApplicationController
  before_action :authenticate_staff_token!

  LEAVE_TYPES = %w[公休 年休 振替休日 夏期休暇 病気休暇 特別休暇].freeze

  def index
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a

    library = @current_staff.library
    holidays = HolidayFetcher.fetch(@target_month.year)
    extra = temporary_closed_dates_map(library, @target_month)
    forced_open = temporary_open_dates_map(library, @target_month)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: library.closed_wdays_array, extra_closed_dates: extra, forced_open_dates: forced_open).closed_days_with_labels

    @input_deadline = library.input_deadlines.find_by(target_month: @target_month.beginning_of_month)
    @submission = MonthlySubmission.find_by(staff: @current_staff, target_month: @target_month.beginning_of_month)

    @existing_leaves = LeaveRequest
      .where(staff: @current_staff, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |lr, h| h[lr.date] = lr.reason.presence || "公休" }

    @existing_substitute_work_dates = LeaveRequest
      .where(staff: @current_staff, date: @target_month.beginning_of_month..@target_month.end_of_month, reason: "振替休日")
      .each_with_object({}) { |lr, h| h[lr.date] = lr.substitute_work_date }

    @existing_hourly_leaves = HourlyLeave
      .where(staff: @current_staff, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |hl, h| h[hl.date] = hl.time_range_label }
  end

  def save
    @target_month = parse_target_month
    leave_types = params[:leave_types]&.to_unsafe_h || {}
    selected_dates = Array(params[:leave_dates]).filter_map { |d| Date.parse(d) rescue nil }
    substitute_work_dates = params[:substitute_work_dates]&.to_unsafe_h || {}
    hourly_leave_labels = params[:hourly_leave_labels]&.to_unsafe_h || {}
    hourly_leave_dates = Array(params[:hourly_leave_dates]).filter_map { |d| Date.parse(d) rescue nil }

    ActiveRecord::Base.transaction do
      LeaveRequest.where(
        staff: @current_staff,
        date:  @target_month.beginning_of_month..@target_month.end_of_month
      ).destroy_all

      selected_dates.each do |date|
        leave_type = leave_types[date.to_s].presence
        leave_type = "公休" unless LEAVE_TYPES.include?(leave_type)
        substitute_date = leave_type == "振替休日" ? (Date.parse(substitute_work_dates[date.to_s]) rescue nil) : nil
        LeaveRequest.create!(staff: @current_staff, date: date, reason: leave_type, substitute_work_date: substitute_date)
      end

      HourlyLeave.where(
        staff: @current_staff,
        date:  @target_month.beginning_of_month..@target_month.end_of_month
      ).destroy_all

      # 同じ日に終日休みと時間休が両方送信された場合は、終日休みを優先し
      # 時間休は登録しない（時間休はその日出勤している前提のため矛盾する）
      (hourly_leave_dates - selected_dates).each do |date|
        HourlyLeave.create!(staff: @current_staff, date: date, time_range_label: hourly_leave_labels[date.to_s].presence)
      end

      submission = MonthlySubmission.find_or_initialize_by(staff: @current_staff, target_month: @target_month.beginning_of_month)
      submission.leave_submitted_at = Time.current
      submission.save!
    end

    redirect_to staff_leave_input_path(token: params[:token], month: @target_month.strftime("%Y-%m")),
                notice: "#{@target_month.strftime('%Y年%-m月')}の希望休を保存しました。"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to staff_leave_input_path(token: params[:token], month: @target_month.strftime("%Y-%m")),
                alert: "保存に失敗しました：#{e.record.errors.full_messages.join('、')}"
  end

  private

  def authenticate_staff_token!
    @current_staff = Staff.find_by(access_token: params[:token])
    return if @current_staff

    render plain: "アクセストークンが無効です。配布されたURLを確認してください。", status: :unauthorized
  end

  def parse_target_month
    if params[:month].present?
      Date.parse("#{params[:month]}-01")
    else
      Date.today.beginning_of_month.next_month
    end
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month.next_month
  end
end
