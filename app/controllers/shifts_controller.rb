class ShiftsController < ApplicationController
  before_action :authenticate_admin!

  def index
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @shift_group = current_library.shift_groups.find_by(target_month: @target_month.beginning_of_month)

    holidays = HolidayFetcher.fetch(@target_month.year)
    closed_calc = ClosedDayCalculator.new(@target_month, holidays)
    working_calc = WorkingDayCalculator.new(@target_month, holidays)
    @closed_days = closed_calc.closed_days_with_labels
    @working_days = { regular: working_calc.regular_staff_days, hourly: working_calc.hourly_staff_days }

    if @shift_group
      shifts = @shift_group.shifts.includes(:staff)
      @shifts_map = shifts.each_with_object({}) do |shift, hash|
        hash[shift.staff_id] ||= {}
        hash[shift.staff_id][shift.date] = shift
      end
    else
      @shifts_map = {}
    end

    # 希望休セット：[staff_id, date]
    @leave_requests_set = LeaveRequest
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .pluck(:staff_id, :date).to_set

    # 年休・夏休・特別・病気休暇セット：[staff_id, date]（出勤日数にカウント）
    @actual_leave_set = ActualLeave
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .pluck(:staff_id, :date).to_set

    # 特定日マップ：date => Set of staff_id（または :all）＋ラベル
    @special_dates_map    = {}
    @special_date_labels  = {}
    SpecialDate.includes(:designated_staffs)
               .where(date: @target_month.beginning_of_month..@target_month.end_of_month)
               .each do |sd|
      @special_date_labels[sd.date] = sd.label if sd.label.present?
      if sd.target_group == "全職員"
        @special_dates_map[sd.date] = :all
      elsif sd.designated_staffs.any?
        @special_dates_map[sd.date] = sd.designated_staffs.map(&:id).to_set
      end
    end

    # 移動図書館マップ：date => Set of staff_id
    @mobile_library_map = {}
    MobileLibrary.includes(mobile_library_routes: :staffs).each do |ml|
      ml.mobile_library_routes.each do |route|
        date = @dates.select { |d| d.wday == route.wday }[route.week_number - 1]
        next if date.nil? || @closed_days.key?(date)
        @mobile_library_map[date] ||= Set.new
        @mobile_library_map[date].merge(route.staffs.map(&:id))
      end
    end

    # 担当定例会議マップ：date => Set of staff_id
    @assignment_map = {}
    current_library.assignments.includes(:staffs).where.not(meeting_wday: nil).each do |assignment|
      @dates.select { |d| d.wday == assignment.meeting_wday && !@closed_days.key?(d) }.each do |date|
        @assignment_map[date] ||= Set.new
        @assignment_map[date].merge(assignment.staffs.map(&:id))
      end
    end

    @snapshot = ShiftSnapshot.find_by(library: current_library, target_month: @target_month.beginning_of_month)
  end

  def confirm
    target_month = parse_target_month
    shift_group = current_library.shift_groups.find_by(target_month: target_month.beginning_of_month)

    unless shift_group
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: "シフトが生成されていません。" and return
    end

    data = shift_group.shifts.includes(:staff).map do |s|
      { staff_id: s.staff_id, staff_name: s.staff.name, date: s.date.to_s,
        is_working: s.is_working, is_early: s.is_early,
        is_post_duty: s.is_post_duty, is_holiday_post_duty: s.is_holiday_post_duty,
        validation_errors: s.validation_errors }
    end

    snapshot = ShiftSnapshot.find_or_initialize_by(
      library: current_library, target_month: target_month.beginning_of_month
    )
    snapshot.snapshot_data = data.to_json
    snapshot.confirmed_at  = Time.current
    snapshot.save!

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")),
                notice: "#{target_month.strftime('%Y年%-m月')}のシフトを確定しました。"
  end

  def restore
    target_month = parse_target_month
    snapshot = ShiftSnapshot.find_by(library: current_library, target_month: target_month.beginning_of_month)

    unless snapshot
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: "確定済みのバックアップが見つかりません。" and return
    end

    shift_group = current_library.shift_groups.find_or_create_by!(target_month: target_month.beginning_of_month)
    shift_group.shifts.delete_all

    snapshot.shifts_data.each do |s|
      next unless Staff.exists?(s["staff_id"])
      shift_group.shifts.create!(
        staff_id:             s["staff_id"],
        date:                 Date.parse(s["date"]),
        is_working:           s["is_working"],
        is_early:             s["is_early"],
        is_post_duty:         s["is_post_duty"],
        is_holiday_post_duty: s["is_holiday_post_duty"],
        validation_errors:    s["validation_errors"]
      )
    end

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")),
                notice: "#{target_month.strftime('%Y年%-m月')}の確定済みシフトを復元しました。"
  end

  def update
    shift = Shift.joins(:shift_group)
                 .where(shift_groups: { library_id: current_library.id })
                 .find(params[:id])
    shift.update!(is_working: !shift.is_working)

    shift_group = shift.shift_group
    holidays = HolidayFetcher.fetch(shift_group.target_month.year)
    closed_days = ClosedDayCalculator.new(shift_group.target_month, holidays).closed_days_with_labels
    shifts_for_validation = shift_group.shifts.includes(:staff).map do |s|
      { staff_name: s.staff.name, date: s.date, is_working: s.is_working, is_holiday_post_duty: s.is_holiday_post_duty }
    end
    ShiftValidationSummary.new(shifts_for_validation, shift_group.target_month, closed_days).save_to_shifts(shift_group)

    redirect_to shifts_path(month: shift_group.target_month.strftime("%Y-%m")),
                notice: "#{shift.date.strftime('%-m月%-d日')}の#{shift.staff.name}のシフトを変更しました。"
  end

  def download
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @shift_group = current_library.shift_groups.find_by(target_month: @target_month.beginning_of_month)

    holidays = HolidayFetcher.fetch(@target_month.year)
    closed_calc = ClosedDayCalculator.new(@target_month, holidays)
    @closed_days = closed_calc.closed_days_with_labels

    if @shift_group
      shifts = @shift_group.shifts.includes(:staff)
      @shifts_map = shifts.each_with_object({}) do |shift, hash|
        hash[shift.staff_id] ||= {}
        hash[shift.staff_id][shift.date] = shift
      end
    else
      @shifts_map = {}
    end

    filename = "シフト表_#{@target_month.strftime('%Y年%m月')}.xlsx"
    response.headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{ERB::Util.url_encode(filename)}"
    render "download", formats: [:xlsx]
  end

  def export
    @target_month = parse_target_month
    @staffs = current_library.staffs.includes(:staff_type, :employment_type).order(:sort_order, :id)
    @shift_group = current_library.shift_groups.find_by(target_month: @target_month.beginning_of_month)

    holidays = HolidayFetcher.fetch(@target_month.year)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays).closed_days_with_labels
    @holidays_in_month = holidays.select { |d, _| d >= @target_month.beginning_of_month && d <= @target_month.end_of_month }
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a

    if @shift_group
      @shifts_map = @shift_group.shifts.includes(:staff).each_with_object({}) do |s, h|
        h[s.staff_id] ||= {}
        h[s.staff_id][s.date] = s
      end
    else
      @shifts_map = {}
    end

    @leave_map = ActualLeave
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .index_by { |l| [l.staff_id, l.date] }

    @special_date_labels = SpecialDate
      .where(library: current_library, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .where.not(label: [nil, ""])
      .pluck(:date, :label).to_h

    filename = "勤務予定表_#{@target_month.strftime('%Y年%m月')}.xlsx"
    response.headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{ERB::Util.url_encode(filename)}"
    render "export", formats: [:xlsx]
  end

  def generate
    target_month = parse_target_month

    staffs = current_library.staffs
    masker = StaffMasker.new(staffs)
    extractor = ConstraintExtractor.new(target_month, current_library)
    constraints = extractor.extract
    builder = PromptBuilder.new(constraints, masker, target_month)
    generator = ShiftGenerator.new(builder)
    result = generator.generate

    unless result[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: result[:error] and return
    end

    parser = ShiftResponseParser.new(masker, staffs, target_month)
    parsed = parser.parse(result[:content])

    unless parsed[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: parsed[:error] and return
    end

    staff_target_days = constraints[:staffs].each_with_object({}) do |s, h|
      h[s[:name]] = s[:monthly_target_days] || constraints[:working_days][:regular]
    end
    fixed_shifts = ShiftPostProcessor.new(
      parsed[:shifts], constraints[:closed_days],
      constraints[:leave_requests], constraints[:special_dates],
      staff_target_days, constraints[:assignment_constraints]
    ).process
    assigned_shifts = DutyAssigner.new(fixed_shifts, constraints, target_month).assign
    saver = ShiftSaver.new(target_month, assigned_shifts, current_library)
    saved = saver.save

    unless saved[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: saved[:error] and return
    end

    shift_group = saved[:shift_group]
    shifts_for_validation = shift_group.shifts.includes(:staff).map do |s|
      { staff_name: s.staff.name, date: s.date, is_working: s.is_working, is_holiday_post_duty: s.is_holiday_post_duty }
    end
    summary = ShiftValidationSummary.new(shifts_for_validation, target_month, constraints[:closed_days])
    summary.save_to_shifts(shift_group)

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")), notice: "シフトを生成しました。"
  end

  private

  def parse_target_month
    if params[:month].present?
      Date.parse("#{params[:month]}-01")
    else
      Date.today.beginning_of_month
    end
  rescue Date::Error
    Date.today.beginning_of_month
  end
end
