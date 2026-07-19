class ShiftsController < ApplicationController
  before_action :authenticate_admin!

  def index
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @shift_group = current_library.shift_groups.find_by(target_month: @target_month.beginning_of_month)

    holidays = HolidayFetcher.fetch(@target_month.year)
    wdays = current_library.closed_wdays_array
    extra = temporary_closed_dates_map(current_library, @target_month)
    @temporary_closed_dates_in_month = extra
    closed_calc = ClosedDayCalculator.new(@target_month, holidays, closed_wdays: wdays, extra_closed_dates: extra)
    working_calc = WorkingDayCalculator.new(@target_month, holidays, closed_wdays: wdays)
    @closed_days = closed_calc.closed_days_with_labels
    @working_days = { regular: working_calc.city_hall_days, hourly: working_calc.hourly_staff_days }

    if @shift_group
      shifts = @shift_group.shifts.includes(:staff)
      @shifts_map = shifts.each_with_object({}) do |shift, hash|
        hash[shift.staff_id] ||= {}
        hash[shift.staff_id][shift.date] = shift
      end
    else
      @shifts_map = {}
    end

    # 希望休マップ：[staff_id, date] => reason
    @leave_requests_map = LeaveRequest
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |lr, h| h[[lr.staff_id, lr.date]] = lr.reason.presence || "公休" }

    # 年休・夏休・特別・病気休暇マップ：[staff_id, date] => leave_type（出勤日数にカウント）
    @actual_leave_map = ActualLeave
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |al, h| h[[al.staff_id, al.date]] = al.leave_type }
    @actual_leave_set = @actual_leave_map.keys.to_set

    # スケジュールマップ：date => Set of staff_id（または :all）＋ラベル（複数対応）
    @special_dates_map   = {}
    @special_date_labels = {}
    SpecialDate.includes(:designated_staffs)
               .where(library: current_library, date: @target_month.beginning_of_month..@target_month.end_of_month)
               .each do |sd|
      if sd.label.present?
        @special_date_labels[sd.date] ||= []
        @special_date_labels[sd.date] << sd.label
      end
      if sd.target_group == "全職員"
        @special_dates_map[sd.date] = :all
      else
        unless @special_dates_map[sd.date] == :all
          @special_dates_map[sd.date] ||= Set.new
          if sd.target_group.present?
            @staffs.select { |s| s.staff_type.name == sd.target_group }.each do |s|
              @special_dates_map[sd.date] << s.id
            end
          end
          @special_dates_map[sd.date].merge(sd.designated_staffs.map(&:id)) if sd.designated_staffs.any?
        end
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

    is_working = params[:is_working] == "1"
    shift.update!(
      is_working:           is_working,
      is_early:             params[:is_early] == "1",
      is_post_duty:         params[:is_post_duty] == "1",
      is_holiday_post_duty: params[:is_holiday_post_duty] == "1"
    )

    leave_type = params[:leave_type]
    if is_working || leave_type.blank? || !ActualLeave::LEAVE_TYPES.key?(leave_type)
      ActualLeave.where(staff_id: shift.staff_id, date: shift.date).delete_all
    else
      al = ActualLeave.find_or_initialize_by(staff_id: shift.staff_id, date: shift.date)
      al.update!(leave_type: leave_type)
    end

    shift_group = shift.shift_group
    holidays = HolidayFetcher.fetch(shift_group.target_month.year)
    extra = temporary_closed_dates_map(current_library, shift_group.target_month)
    closed_days = ClosedDayCalculator.new(shift_group.target_month, holidays,
                    closed_wdays: current_library.closed_wdays_array, extra_closed_dates: extra).closed_days_with_labels
    shifts_for_validation = shift_group.shifts.includes(:staff).map do |s|
      { staff_name: s.staff.name, date: s.date, is_working: s.is_working, is_holiday_post_duty: s.is_holiday_post_duty }
    end
    ShiftValidationSummary.new(shifts_for_validation, shift_group.target_month, closed_days, current_library).save_to_shifts(shift_group)

    shift.update_column(:validation_errors, nil) if params[:clear_errors] == "1"

    redirect_to shifts_path(month: shift_group.target_month.strftime("%Y-%m")),
                notice: "#{shift.date.strftime('%-m月%-d日')}の#{shift.staff.name}のシフトを変更しました。"
  end

  def download
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a
    @staffs = current_library.staffs.includes(:staff_type).order(:sort_order, :id)
    @shift_group = current_library.shift_groups.find_by(target_month: @target_month.beginning_of_month)

    holidays = HolidayFetcher.fetch(@target_month.year)
    extra = temporary_closed_dates_map(current_library, @target_month)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: current_library.closed_wdays_array, extra_closed_dates: extra).closed_days_with_labels

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
    extra = temporary_closed_dates_map(current_library, @target_month)
    @closed_days = ClosedDayCalculator.new(@target_month, holidays,
                     closed_wdays: current_library.closed_wdays_array, extra_closed_dates: extra).closed_days_with_labels
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

    @leave_requests_map = LeaveRequest
      .where(staff: @staffs, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .each_with_object({}) { |lr, h| h[[lr.staff_id, lr.date]] = lr.reason.presence || "公休" }

    @special_date_labels = {}
    @special_dates_for_export = SpecialDate
      .includes(:designated_staffs)
      .where(library: current_library, date: @target_month.beginning_of_month..@target_month.end_of_month)
      .order(:date)
    @special_dates_for_export.each do |sd|
      next if sd.label.blank?
      (@special_date_labels[sd.date] ||= []) << sd.label
    end

    # スケジュール・移動図書館・担当会議マップ: [staff_id, date] => true
    @schedule_map = {}
    @special_dates_for_export.each do |sd|
      if sd.target_group == "全職員"
        @staffs.each { |s| @schedule_map[[s.id, sd.date]] = true }
      else
        if sd.target_group.present?
          @staffs.select { |s| s.staff_type.name == sd.target_group }.each { |s| @schedule_map[[s.id, sd.date]] = true }
        end
        sd.designated_staffs.each { |s| @schedule_map[[s.id, sd.date]] = true } if sd.designated_staffs.any?
      end
    end
    MobileLibrary.includes(mobile_library_routes: :staffs).where(library: current_library).each do |ml|
      ml.mobile_library_routes.each do |route|
        date = @dates.select { |d| d.wday == route.wday }[route.week_number - 1]
        next if date.nil? || @closed_days.key?(date)
        route.staffs.each { |s| @schedule_map[[s.id, date]] = true }
      end
    end
    current_library.assignments.includes(:staffs).where.not(meeting_wday: nil).each do |assignment|
      @dates.select { |d| d.wday == assignment.meeting_wday && !@closed_days.key?(d) }.each do |date|
        assignment.staffs.each { |s| @schedule_map[[s.id, date]] = true }
      end
    end

    filename = "勤務予定表_#{@target_month.strftime('%Y年%m月')}.xlsx"
    response.headers["Content-Disposition"] = "attachment; filename*=UTF-8''#{ERB::Util.url_encode(filename)}"
    render "export", formats: [:xlsx]
  end

  def suppress_errors
    target_month = parse_target_month
    shift_group = current_library.shift_groups.find_by(target_month: target_month.beginning_of_month)

    unless shift_group
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: "シフトが生成されていません。" and return
    end

    shift_group.update!(suppress_all_errors: true)
    shift_group.shifts.update_all(validation_errors: nil)

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")),
                notice: "バリデーションエラーを非表示にしました。"
  end

  def restore_errors
    target_month = parse_target_month
    shift_group = current_library.shift_groups.find_by(target_month: target_month.beginning_of_month)

    unless shift_group
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: "シフトが生成されていません。" and return
    end

    shift_group.update!(suppress_all_errors: false)
    holidays = HolidayFetcher.fetch(target_month.year)
    extra = temporary_closed_dates_map(current_library, target_month)
    closed_days = ClosedDayCalculator.new(target_month, holidays,
                    closed_wdays: current_library.closed_wdays_array, extra_closed_dates: extra).closed_days_with_labels
    shifts_for_validation = shift_group.shifts.includes(:staff).map do |s|
      { staff_name: s.staff.name, date: s.date, is_working: s.is_working, is_holiday_post_duty: s.is_holiday_post_duty }
    end
    ShiftValidationSummary.new(shifts_for_validation, target_month, closed_days, current_library).save_to_shifts(shift_group)

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")),
                notice: "バリデーションエラーを再表示しました。"
  end

  def destroy_group
    target_month = parse_target_month
    shift_group = current_library.shift_groups.find_by(target_month: target_month.beginning_of_month)

    unless shift_group
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: "削除するシフトデータがありません。" and return
    end

    ShiftSnapshot.where(library: current_library, target_month: target_month.beginning_of_month).destroy_all
    shift_group.destroy

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")),
                notice: "#{target_month.strftime('%Y年%-m月')}の生成データを削除しました。"
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
      staff_target_days, constraints[:assignment_constraints],
      constraints[:mobile_library_constraints]
    ).process
    assigned_shifts = DutyAssigner.new(fixed_shifts, constraints, target_month).assign
    saver = ShiftSaver.new(target_month, assigned_shifts, current_library)
    saved = saver.save

    unless saved[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: saved[:error] and return
    end

    shift_group = saved[:shift_group]
    shift_group.update!(suppress_all_errors: false)
    shifts_for_validation = shift_group.shifts.includes(:staff).map do |s|
      { staff_name: s.staff.name, date: s.date, is_working: s.is_working, is_holiday_post_duty: s.is_holiday_post_duty }
    end
    summary = ShiftValidationSummary.new(shifts_for_validation, target_month, constraints[:closed_days], current_library)
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
