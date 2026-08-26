class LeaveRequestsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_leave_request, only: %i[edit update destroy]

  LEAVE_TYPES = %w[公休 年休 夏期休暇 病気休暇 特別休暇].freeze

  def index
    @target_month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month.next_month
    @leave_requests = LeaveRequest.includes(:staff)
                        .where(staff: current_library.staffs)
                        .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
                        .order(:date, "staffs.sort_order", "staffs.id")
    @leave_requests_by_staff = @leave_requests.group_by(&:staff)
                                 .sort_by { |staff, _| [staff.sort_order, staff.id] }
  end

  # 職員向け希望休入力画面（休暇種別を選んでカレンダーの日付をタップする方式）
  # と同じ操作感で、管理者が対象の職員を選んで登録できるようにする
  def new
    set_form_options
    @target_month = parse_target_month
    @staff = @staffs.find_by(id: params[:staff_id])
    return unless @staff

    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a
    holidays = HolidayFetcher.fetch(@target_month.year)
    extra = temporary_closed_dates_map(current_library, @target_month)
    forced_open = temporary_open_dates_map(current_library, @target_month)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: current_library.closed_wdays_array, extra_closed_dates: extra, forced_open_dates: forced_open).closed_days_with_labels
    @existing_leaves = LeaveRequest
      .where(staff: @staff, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |lr, h| h[lr.date] = lr.reason.presence || "公休" }
  end

  # new画面のカレンダーで選んだ内容を一括保存する（対象月の希望休を一旦全て
  # 削除してから、選択された分だけ作り直す。職員向け入力と同じ方式）
  def save
    target_month = parse_target_month
    staff = current_library.staffs.find_by(id: params[:staff_id])
    unless staff
      redirect_to new_leave_request_path(month: target_month.strftime("%Y-%m")), alert: "職員を選択してください。" and return
    end

    leave_types = params[:leave_types]&.to_unsafe_h || {}
    selected_dates = Array(params[:leave_dates]).filter_map { |d| Date.parse(d) rescue nil }

    LeaveRequest.where(staff: staff, date: target_month.beginning_of_month..target_month.end_of_month).destroy_all

    selected_dates.each do |date|
      leave_type = leave_types[date.to_s].presence
      leave_type = "公休" unless LEAVE_TYPES.include?(leave_type)
      LeaveRequest.create!(staff: staff, date: date, reason: leave_type)
    end

    redirect_to leave_requests_path(month: target_month.strftime("%Y-%m")),
                notice: "#{staff.name}さんの#{target_month.strftime('%Y年%-m月')}の希望休を保存しました。"
  end

  def edit
    set_form_options
  end

  def update
    if @leave_request.update(leave_request_params)
      tab = params[:from] == "by-staff" ? "by-staff" : nil
      redirect_to leave_requests_path(month: @leave_request.date.strftime("%Y-%m"), tab: tab), notice: "希望休を更新しました。"
    else
      set_form_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @leave_request.destroy
    tab = params[:from] == "by-staff" ? "by-staff" : nil
    redirect_to leave_requests_path(month: @leave_request.date.strftime("%Y-%m"), tab: tab), notice: "希望休を削除しました。"
  end

  private

  def set_leave_request
    @leave_request = LeaveRequest.where(staff: current_library.staffs).find(params[:id])
  end

  def set_form_options
    @staffs = current_library.staffs.order(:sort_order, :id)
  end

  def parse_target_month
    params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.today.beginning_of_month.next_month
  rescue ArgumentError, TypeError
    Date.today.beginning_of_month.next_month
  end

  def leave_request_params
    params.require(:leave_request).permit(:staff_id, :date, :reason, :note)
  end
end
