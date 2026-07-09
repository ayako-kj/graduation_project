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
    eligible = eligible_names("会計年度任用職員", EARLY_STAFF_TYPES)
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
    eligible = eligible_names("正規職員", %w[司書])
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
    eligible = eligible_names("正規職員", %w[司書])
    return if eligible.empty?

    counts = historical_counts(eligible, :is_holiday_post_duty)
    (@dc[:holiday_post_duty_dates] || {}).each_key do |date|
      assignee = eligible.min_by { |name| counts[name] }
      set_field(assignee, date, :is_holiday_post_duty, true)
      set_field(assignee, date, :is_working, true)
      counts[assignee] += 1
    end
  end

  def eligible_names(employment_type, staff_types)
    @constraints[:staffs].select do |s|
      s[:employment_type] == employment_type && staff_types.include?(s[:staff_type])
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
end
