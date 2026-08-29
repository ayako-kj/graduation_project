class ConstraintExtractor
  def initialize(target_month, library)
    @target_month = target_month
    @library = library
    @start_date = target_month.beginning_of_month
    @end_date = target_month.end_of_month
  end

  def extract
    @holidays = HolidayFetcher.fetch(@target_month.year)
    fiscal_year = @target_month.month >= 4 ? @target_month.year : @target_month.year - 1
    @all_holidays = if fiscal_year == @target_month.year
      @holidays
    else
      HolidayFetcher.fetch(fiscal_year).merge(@holidays)
    end
    wdays = @library.closed_wdays_array
    extra = TemporaryClosedDate
      .where(library: @library, date: @start_date..@end_date)
      .each_with_object({}) { |tcd, h| h[tcd.date] = tcd.label.presence || "臨時公休日" }
    forced_open = TemporaryOpenDate
      .where(library: @library, date: @start_date..@end_date)
      .each_with_object({}) { |tod, h| h[tod.date] = tod.label.presence || "臨時出勤日" }
    @closed_calc = ClosedDayCalculator.new(@target_month, @holidays, closed_wdays: wdays, extra_closed_dates: extra, forced_open_dates: forced_open)
    @working_calc = WorkingDayCalculator.new(@target_month, @holidays, closed_wdays: wdays)
    @n_city_hall = @working_calc.city_hall_days
    @closed_days_with_labels = @closed_calc.closed_days_with_labels

    {
      staffs: staffs_data,
      placement_rules: placement_rules_data,
      special_dates: special_dates_data,
      leave_requests: leave_requests_data,
      closed_days: @closed_days_with_labels,
      working_days: {
        regular: @working_calc.city_hall_days,
        hourly: @working_calc.hourly_staff_days
      },
      duty_constraints: duty_constraints_data,
      assignment_constraints: assignment_constraints_data,
      mobile_library_constraints: mobile_library_constraints_data,
      prior_trailing_work_days: prior_trailing_work_days_data
    }
  end

  private

  def duty_constraints_data
    {
      early_shift_dates: early_shift_dates,
      post_duty_dates: post_duty_dates,
      holiday_post_duty_dates: holiday_post_duty_dates
    }
  end

  def early_shift_dates
    (@start_date..@end_date).select do |date|
      !@closed_days_with_labels.key?(date) && !last_wednesday_of_month?(date)
    end
  end

  def post_duty_dates
    # 月曜祝日の翌々日（水曜）は通常ポスト当番をスキップ
    monday_holidays_in_month = @holidays.keys.select { |d| d >= @start_date && d <= @end_date && d.monday? }
    skip_wednesdays = monday_holidays_in_month.map { |d| d + 2 }.to_set
    (@start_date..@end_date).select do |date|
      date.wednesday? && !last_wednesday_of_month?(date) && !@holidays.key?(date) &&
        !skip_wednesdays.include?(date)
    end
  end

  def holiday_post_duty_dates
    result = {}
    @holidays.each do |d, label|
      next unless d >= @start_date && d <= @end_date
      if d.monday?
        # 月曜祝日は翌火曜日に祝日ポスト当番を振替
        tuesday = d + 1
        result[tuesday] = label if tuesday <= @end_date
      else
        result[d] = label
      end
    end
    result
  end

  def last_wednesday_of_month?(date)
    date.wednesday? && (date + 7).month != date.month
  end

  def mobile_library_constraints_data
    MobileLibrary.includes(mobile_library_routes: [:staffs, :mobile_library_exceptions]).where(library: @library).flat_map do |ml|
      ml.mobile_library_routes.filter_map do |route|
        occurrence = route.occurrence_for(@target_month, closed_days: @closed_days_with_labels)
        next if occurrence.nil?
        {
          route_name: "#{ml.name}#{route.name}",
          staff_names: occurrence.staffs.map(&:name),
          date: occurrence.date.strftime("%Y-%m-%d")
        }
      end
    end
  end

  def assignment_constraints_data
    Assignment.includes(:staffs).where(library: @library).where.not(meeting_wday: nil).map do |assignment|
      dates = (@start_date..@end_date).select { |d| d.wday == assignment.meeting_wday && !@closed_days_with_labels.key?(d) }
      next if dates.empty? || assignment.staffs.empty?
      {
        name: assignment.name,
        staff_names: assignment.staffs.map(&:name),
        dates: dates.map { |d| d.strftime("%Y-%m-%d") }
      }
    end.compact
  end

  def staffs_data
    fiscal_year = @target_month.month >= 4 ? @target_month.year : @target_month.year - 1
    fiscal_months = (4..12).map { |m| Date.new(fiscal_year, m, 1) } +
                    (1..3).map { |m| Date.new(fiscal_year + 1, m, 1) }
    past_months = fiscal_months.select { |m| m < @target_month.beginning_of_month }

    staffs = @library.staffs.includes(:staff_type, :employment_type)
    actual_data = past_months.any? ? preload_past_actual_data(staffs, past_months) : {}
    wc_debt = past_months.any? ? weekend_consecutive_debt_data(staffs, past_months) : {}

    staffs.map do |staff|
      is_regular = staff.employment_type.is_regular
      base_days = if is_regular
        @n_city_hall
      else
        (@n_city_hall * staff.employment_type.city_hall_daily_hours / staff.effective_daily_work_hours).floor
      end
      monthly_target = calculate_monthly_target(staff, base_days, past_months, actual_data)

      {
        name: staff.name,
        staff_type: staff.staff_type.name,
        employment_type: staff.employment_type.name,
        is_regular: staff.employment_type.is_regular,
        weekly_work_days: staff.weekly_work_days,
        unavailable_wdays: staff.unavailable_wdays_array,
        monthly_target_days: monthly_target,
        weekend_consecutive_debt: wc_debt[staff.id] || 0
      }
    end
  end

  # 今年度これまでに、土日連続勤務を何回したか（work_count）と、
  # 土日連続休み（家庭の事情等での希望休）を何回取ったか（off_count）を
  # 集計し、「off_count - work_count」を返す。値が大きい職員ほど、
  # 土日連続休みを取った分に見合うだけの土日連続勤務をまだしていない
  # （＝次に土日連続勤務が避けられない場面では、この職員に割り当てる
  # のが公平）とみなす。逆に値が小さい（マイナスの）職員ほど、既に
  # 土日連続勤務を多くこなしているため、優先して救済（片方をキャンセル）
  # する対象になる
  def weekend_consecutive_debt_data(staffs, past_months)
    start_date = past_months.first.beginning_of_month
    end_date = past_months.last.end_of_month
    staff_ids = staffs.map(&:id)

    work_count = Hash.new(0)
    @library.shift_groups.where(target_month: past_months.first..past_months.last).each do |sg|
      dates_by_staff = Shift.where(shift_group: sg, is_working: true)
        .group_by(&:staff_id)
        .transform_values { |list| list.map(&:date).to_set }
      dates_by_staff.each do |staff_id, dates|
        dates.each do |d|
          next unless d.saturday? && dates.include?(d + 1)
          work_count[staff_id] += 1
        end
      end
    end

    off_count = Hash.new(0)
    LeaveRequest.where(staff_id: staff_ids, date: start_date..end_date)
      .group_by(&:staff_id)
      .each do |staff_id, list|
        dates = list.map(&:date).to_set
        dates.each do |d|
          next unless d.saturday? && dates.include?(d + 1)
          off_count[staff_id] += 1
        end
      end

    # Pitat導入前（手入力）の実績も合算する
    WorkdayManualEntry.where(staff_id: staff_ids, year_month: past_months.first..past_months.last).each do |e|
      work_count[e.staff_id] += e.weekend_consecutive_work_count || 0
      off_count[e.staff_id]  += e.weekend_consecutive_off_count || 0
    end

    staff_ids.each_with_object({}) { |id, h| h[id] = off_count[id] - work_count[id] }
  end

  def preload_past_actual_data(staffs, past_months)
    start_date = past_months.first
    end_date = past_months.last
    staff_ids = staffs.map(&:id)

    manual_map = WorkdayManualEntry
      .where(staff_id: staff_ids, year_month: start_date..end_date)
      .index_by { |e| [e.staff_id, e.year_month] }

    shift_groups = @library.shift_groups.where(target_month: start_date..end_date)
    pitat_map = {}
    shift_groups.each do |sg|
      Shift.where(shift_group: sg, is_working: true).group(:staff_id).count.each do |staff_id, count|
        pitat_map[[staff_id, sg.target_month]] = count
      end
      # 年休・夏期休暇・病気休暇・特別休暇（ActualLeave）も勤務日数実績に含める。
      # これを含めないと、有給休暇を取った月の目標日数の繰越調整が働かず、
      # 累計差が正しく解消されない
      month_start = sg.target_month.beginning_of_month
      month_end   = sg.target_month.end_of_month
      ActualLeave.where(staff_id: staff_ids, date: month_start..month_end)
                 .group(:staff_id).count.each do |staff_id, count|
        pitat_map[[staff_id, sg.target_month]] = (pitat_map[[staff_id, sg.target_month]] || 0) + count
      end
    end
    sg_months = Set.new(shift_groups.map(&:target_month))

    { manual: manual_map, pitat: pitat_map, sg_months: sg_months }
  end

  # 正規職員・会計年度任用職員共通の、過去月の累積誤差を今月の目標日数に
  # 繰り越すための調整計算。1日あたりの勤務時間は雇用形態・職員ごとに異なる
  # （正規職員=市役所と同一、会計年度任用職員=7.5h/市役所6.0h）ため、
  # 誤差は一旦「時間」で積算し、最後に自分の1日あたり時間で日数に変換する。
  def calculate_monthly_target(staff, base_days, past_months, actual_data)
    daily_hours = staff.effective_daily_work_hours
    city_hall_daily = staff.employment_type.city_hall_daily_hours

    cumulative_diff = 0.0
    past_months.each do |month|
      key = [staff.id, month.beginning_of_month]
      actual = if actual_data[:manual][key]
        actual_data[:manual][key].working_days
      elsif actual_data[:sg_months].include?(month.beginning_of_month)
        actual_data[:pitat][key] || 0
      end

      # 実績未記録の月はfloor丸めの目標値を実績とみなすとベースラインに誤差が
      # 蓄積するため、誤差計算の対象から除外する
      next if actual.nil?

      n = WorkingDayCalculator.new(month, @all_holidays, closed_wdays: []).city_hall_days
      cumulative_diff += actual * daily_hours - n * city_hall_daily
    end

    # 累計差は毎月0に近づけることを目標にする。1日単位でしかシフトを組めない
    # ため、四捨五入で達成可能な範囲で最も0に近い日数にする（端数が残っても
    # 日あたり勤務時間分＝正規職員1日・会計年度任用職員7.5時間以内に収まる）。
    extra = (-cumulative_diff / daily_hours).round
    [[base_days + extra, 0].max, @n_city_hall].min
  end

  def placement_rules_data
    PlacementRule.includes(:staff_type, :employment_type).map do |rule|
      case rule.rule_type
      when "min_count"
        emp = rule.employment_type ? "（#{rule.employment_type.name}）" : ""
        { rule_type: "min_count", staff_type: "#{rule.staff_type.name}#{emp}", min_count: rule.min_count }
      when "at_least_one_of"
        names = StaffType.where(id: rule.staff_type_ids_array).pluck(:name)
        { rule_type: "at_least_one_of", staff_types: names }
      when "team_min"
        names = StaffType.where(id: rule.staff_type_ids_array).pluck(:name)
        { rule_type: "team_min", staff_types: names, min_count: rule.min_count }
      end
    end.compact
  end

  def special_dates_data
    SpecialDate.includes(:designated_staffs).where(library: @library, date: @start_date..@end_date).map do |sd|
      {
        date: sd.date.strftime("%Y-%m-%d"),
        label: sd.label,
        target_group: sd.target_group,
        designated_staffs: sd.designated_staffs.map(&:name)
      }
    end
  end

  # 前月末時点で、各職員が何日連続で出勤していたか（当月1日の前日から
  # 遡って数える）。シフトは月ごとに独立して生成されるため、これが無いと
  # 前月末〜当月頭にまたがる連勤（例：9/27〜10/3の7連勤）を検知・回避
  # できない。前月のShiftGroupが無ければ空のハッシュを返す
  def prior_trailing_work_days_data
    prev_month = @target_month.prev_month.beginning_of_month
    sg = @library.shift_groups.find_by(target_month: prev_month)
    return {} unless sg

    dates_by_staff = Shift.where(shift_group: sg, is_working: true)
      .group_by(&:staff_id)
      .transform_values { |list| list.map(&:date).to_set }
    staff_names = @library.staffs.where(id: dates_by_staff.keys).index_by(&:id).transform_values(&:name)

    dates_by_staff.each_with_object({}) do |(staff_id, dates), result|
      name = staff_names[staff_id]
      next unless name

      count = 0
      d = @start_date - 1
      while dates.include?(d) && count < ConsecutiveWorkValidator::MAX_CONSECUTIVE_DAYS
        count += 1
        d -= 1
      end
      result[name] = count if count > 0
    end
  end

  def leave_requests_data
    LeaveRequest.includes(:staff)
                .where(staff: @library.staffs, date: @start_date..@end_date)
                .map do |lr|
      {
        staff_name: lr.staff.name,
        date: lr.date.strftime("%Y-%m-%d"),
        reason: lr.reason
      }
    end
  end
end
