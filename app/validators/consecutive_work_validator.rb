class ConsecutiveWorkValidator
  MAX_CONSECUTIVE_DAYS = 5

  def initialize(shifts)
    @shifts = shifts
  end

  def validate
    violations = []
    shifts_by_staff = @shifts.group_by { |s| s[:staff_name] }

    shifts_by_staff.each do |staff_name, staff_shifts|
      working_dates = staff_shifts
        .select { |s| s[:is_working] && !s[:is_holiday_post_duty] }
        .map { |s| s[:date] }
        .sort

      consecutive_groups = find_consecutive_groups(working_dates)
      consecutive_groups.each do |group|
        if group.size > MAX_CONSECUTIVE_DAYS
          violations << {
            staff_name: staff_name,
            start_date: group.first,
            end_date: group.last,
            consecutive_days: group.size,
            message: "#{staff_name}が#{group.first.strftime('%m月%d日')}〜#{group.last.strftime('%m月%d日')}に#{group.size}連勤になっています"
          }
        end
      end
    end

    violations.sort_by { |v| [v[:start_date], v[:staff_name]] }
  end

  def valid?
    validate.empty?
  end

  private

  def find_consecutive_groups(dates)
    return [] if dates.empty?

    groups = []
    current_group = [dates.first]

    dates[1..].each do |date|
      if date == current_group.last + 1
        current_group << date
      else
        groups << current_group
        current_group = [date]
      end
    end
    groups << current_group
    groups
  end
end
