class TotalCountValidator
  MIN_STAFF_COUNT = 12

  def initialize(shifts, closed_days = {})
    @shifts = shifts
    @closed_days = closed_days
  end

  def validate
    violations = []

    shifts_by_date = @shifts.group_by { |s| s[:date] }
    shifts_by_date.each do |date, day_shifts|
      next if @closed_days.key?(date)
      working_count = day_shifts.count { |s| s[:is_working] }
      if working_count < MIN_STAFF_COUNT
        violations << {
          date: date,
          working_count: working_count,
          message: "#{date.strftime('%m月%d日')}の出勤人数が#{working_count}人です（最低#{MIN_STAFF_COUNT}人必要）"
        }
      end
    end

    violations.sort_by { |v| v[:date] }
  end

  def valid?
    validate.empty?
  end
end
