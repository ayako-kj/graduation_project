class DutyAssigner
  EARLY_STAFF_TYPES = %w[専門司書 司書].freeze

  def initialize(parsed_shifts, constraints, target_month, library)
    @shifts = parsed_shifts
    @constraints = constraints
    @target_month = target_month
    @library = library
    @dc = constraints[:duty_constraints] || {}
    # 移動図書館巡回日: {date => [staff_name, ...]}
    @mobile_library_staff_by_date = (constraints[:mobile_library_constraints] || []).each_with_object(Hash.new { |h, k| h[k] = [] }) do |mc, h|
      h[Date.parse(mc[:date])].concat(mc[:staff_names])
    end
    # 時間休の日: {date => [staff_name, ...]}（出勤扱いのまま、早番・当番の対象からのみ外す）
    @hourly_leave_staff_by_date = (constraints[:hourly_leave_constraints] || []).each_with_object(Hash.new { |h, k| h[k] = [] }) do |hl, h|
      h[Date.parse(hl[:date])] << hl[:staff_name]
    end
  end

  def assign
    assign_early_shifts
    assign_post_duties
    assign_holiday_post_duties
    @shifts
  end

  private

  def assign_early_shifts
    eligible = eligible_names_non_regular(EARLY_STAFF_TYPES)
    return if eligible.empty?

    counts = historical_counts(eligible, :is_early, :early_count)
    (@dc[:early_shift_dates] || []).each do |date|
      # 移動図書館の巡回担当は、巡回後の作業ができなくなるため早番にしない。
      # 時間休の職員も、時間帯が重なる可能性があるため早番にしない
      working = working_eligible(eligible, date) - @mobile_library_staff_by_date[date] - @hourly_leave_staff_by_date[date]
      next if working.empty?

      assignee = working.shuffle.min_by { |name| counts[name] }
      set_field(assignee, date, :is_early, true)
      counts[assignee] += 1
    end
  end

  def assign_post_duties
    eligible = eligible_names_regular(%w[司書])
    return if eligible.empty?

    counts = historical_counts(eligible, :is_post_duty, :post_duty_count)
    (@dc[:post_duty_dates] || []).each do |date|
      # 時間休の職員は、時間帯が重なる可能性があるためポスト当番にしない
      working = working_eligible(eligible, date) - @hourly_leave_staff_by_date[date]
      next if working.empty?

      assignee = working.shuffle.min_by { |name| counts[name] }
      set_field(assignee, date, :is_post_duty, true)
      counts[assignee] += 1
    end
  end

  def assign_holiday_post_duties
    eligible = eligible_names_regular(%w[司書])
    return if eligible.empty?

    counts = historical_counts(eligible, :is_holiday_post_duty, :holiday_post_duty_count)
    (@dc[:holiday_post_duty_dates] || {}).each_key do |date|
      # 時間休の職員は、時間帯が重なる可能性があるため祝日ポスト当番にしない
      eligible_today = eligible - @hourly_leave_staff_by_date[date]
      next if eligible_today.empty?

      # 連続勤務違反を引き起こさない人を優先して選ぶ
      safe = eligible_today.reject { |name| would_cause_consecutive_violation?(name, date) }
      candidates = safe.any? ? safe : eligible_today
      assignee = candidates.shuffle.min_by { |name| counts[name] }
      set_field(assignee, date, :is_holiday_post_duty, true)
      set_field(assignee, date, :is_working, true)
      counts[assignee] += 1
    end
  end

  def eligible_names_regular(staff_types)
    @constraints[:staffs].select do |s|
      s[:is_regular] && staff_types.include?(s[:staff_type])
    end.map { |s| s[:name] }
  end

  def eligible_names_non_regular(staff_types)
    @constraints[:staffs].select do |s|
      !s[:is_regular] && staff_types.include?(s[:staff_type])
    end.map { |s| s[:name] }
  end

  def working_eligible(eligible, date)
    @shifts.select { |s| s[:date] == date && s[:is_working] && eligible.include?(s[:staff_name]) }
           .map { |s| s[:staff_name] }
  end

  # Pitat導入前の実績（WorkdayManualEntry）を含めないと、既に偏った実績のある
  # 職員を「実績0人」と誤認して割り当ててしまい、偏りを助長するため合算する。
  # シフト表は年度（4月始まり）ごとに作成する運用のため、実績は今年度分のみを集計する
  def historical_counts(staff_names, duty_field, manual_field)
    fiscal_year_start = fiscal_year_start_for(@target_month)
    fiscal_months_so_far = fiscal_months_before_target(fiscal_year_start)

    counts = Hash.new(0)
    hired_on_by_name = {}

    staff_names.each do |name|
      staff = @library.staffs.find_by(name: name)
      next unless staff

      auto_count = Shift.joins(:shift_group)
                        .where(staff: staff, duty_field => true)
                        .where("shift_groups.target_month >= ? AND shift_groups.target_month < ?",
                               fiscal_year_start, @target_month.beginning_of_month)
                        .count
      manual_count = WorkdayManualEntry
                        .where(staff: staff)
                        .where("year_month >= ? AND year_month < ?", fiscal_year_start, @target_month.beginning_of_month)
                        .sum(manual_field)
      counts[name] = auto_count + manual_count
      hired_on_by_name[name] = staff.hired_on
    end

    # 年度途中で入社した職員は、在籍していなかった月の分だけ実績が
    # 少なくなるのが当然で「出遅れている」わけではない。放置すると常に
    # 最優先で割り当てられて早番・当番が偏って集中してしまうため、
    # 4月から在籍していた場合に見込まれたであろう実績（既存職員の
    # 月平均実績×不在月数）をあらかじめ加算し、公平な比較に揃える
    established_names = staff_names.select do |name|
      hired_on = hired_on_by_name[name]
      hired_on.nil? || hired_on <= fiscal_year_start
    end

    if established_names.any? && fiscal_months_so_far.any?
      established_avg = established_names.sum { |name| counts[name] }.to_f / established_names.size
      monthly_rate = established_avg / fiscal_months_so_far.size

      (staff_names - established_names).each do |name|
        hired_on = hired_on_by_name[name]
        next unless hired_on

        months_absent = fiscal_months_so_far.count { |m| hired_on >= m.next_month }
        counts[name] += (monthly_rate * months_absent).round
      end
    end

    counts
  end

  def fiscal_year_start_for(month)
    fiscal_year = month.month >= 4 ? month.year : month.year - 1
    Date.new(fiscal_year, 4, 1)
  end

  def fiscal_months_before_target(fiscal_year_start)
    months = []
    m = fiscal_year_start
    while m < @target_month.beginning_of_month
      months << m
      m = m.next_month
    end
    months
  end

  def set_field(staff_name, date, field, value)
    shift = @shifts.find { |s| s[:staff_name] == staff_name && s[:date] == date }
    shift[field] = value if shift
  end

  def would_cause_consecutive_violation?(staff_name, date)
    staff_shifts = @shifts.select { |s| s[:staff_name] == staff_name }
    working_dates = staff_shifts.select { |s| s[:is_working] }.map { |s| s[:date] }.sort
    test_dates = (working_dates + [date]).uniq.sort
    groups = find_consecutive_date_groups(test_dates)
    groups.any? { |g| g.size > ConsecutiveWorkValidator::MAX_CONSECUTIVE_DAYS }
  end

  def find_consecutive_date_groups(dates)
    return [] if dates.empty?
    groups = []
    current = [dates.first]
    dates[1..].each do |date|
      date == current.last + 1 ? current << date : (groups << current; current = [date])
    end
    groups << current
    groups
  end
end
