class DutyAssigner
  EARLY_STAFF_TYPES = %w[専門司書 司書].freeze

  def initialize(parsed_shifts, constraints, target_month)
    @shifts = parsed_shifts
    @constraints = constraints
    @target_month = target_month
    @dc = constraints[:duty_constraints] || {}
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

    counts = historical_counts(eligible, :is_early)
    (@dc[:early_shift_dates] || []).each do |date|
      working = working_eligible(eligible, date)
      next if working.empty?

      assignee = working.min_by { |name| counts[name] }
      set_field(assignee, date, :is_early, true)
      counts[assignee] += 1
    end
  end

  def assign_post_duties
    eligible = eligible_names_regular(%w[司書])
    return if eligible.empty?

    counts = historical_counts(eligible, :is_post_duty)
    (@dc[:post_duty_dates] || []).each do |date|
      working = working_eligible(eligible, date)
      next if working.empty?

      assignee = working.min_by { |name| counts[name] }
      set_field(assignee, date, :is_post_duty, true)
      counts[assignee] += 1
    end
  end

  def assign_holiday_post_duties
    eligible = eligible_names_regular(%w[司書])
    return if eligible.empty?

    counts = historical_counts(eligible, :is_holiday_post_duty)
    (@dc[:holiday_post_duty_dates] || {}).each_key do |date|
      # 連続勤務違反を引き起こさない人を優先して選ぶ
      safe = eligible.reject { |name| would_cause_consecutive_violation?(name, date) }
      candidates = safe.any? ? safe : eligible
      assignee = candidates.min_by { |name| counts[name] }
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

  def historical_counts(staff_names, duty_field)
    counts = Hash.new(0)
    staff_names.each do |name|
      staff = Staff.find_by(name: name)
      next unless staff

      counts[name] = Shift.joins(:shift_group)
                          .where(staff: staff, duty_field => true)
                          .where("shift_groups.target_month < ?", @target_month.beginning_of_month)
                          .count
    end
    counts
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
