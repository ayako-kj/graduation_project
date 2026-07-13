class ShiftPostProcessor
  def initialize(parsed_shifts, closed_days, leave_requests = [], special_dates = [], staff_target_days = {}, assignment_constraints = [])
    @shifts = parsed_shifts
    @closed_days = closed_days
    @staff_target_days = staff_target_days
    @leave_set = leave_requests.each_with_object(Set.new) do |lr, set|
      set << [lr[:staff_name], Date.parse(lr[:date])]
    end
    @all_staff_dates = special_dates.each_with_object(Set.new) do |sd, set|
      set << Date.parse(sd[:date]) if sd[:target_group] == "全職員"
    end
    @designated_dates = special_dates.each_with_object({}) do |sd, h|
      next if sd[:designated_staffs].empty?
      h[Date.parse(sd[:date])] = sd[:designated_staffs]
    end
    # 担当会議日: {date => [staff_name, ...]}
    @assignment_dates = assignment_constraints.each_with_object({}) do |ac, h|
      ac[:dates].each do |date_str|
        date = Date.parse(date_str)
        h[date] ||= []
        h[date].concat(ac[:staff_names])
      end
    end
    @staff_info = build_staff_info
    @rules = build_rules
  end

  def process
    fix_closed_days
    fix_special_dates
    fix_assignment_dates
    fix_excess_staff
    fix_weekend_consecutive
    5.times do
      snapshot = @shifts.map { |s| s[:is_working] }
      fix_consecutive_work
      @shifts.group_by { |s| s[:date] }.each do |date, day_shifts|
        next if @closed_days.key?(date)
        fix_day(day_shifts)
      end
      break if @shifts.map { |s| s[:is_working] } == snapshot
    end
    fix_target_days
    fix_excess_days
    @shifts
  end

  private

  def build_staff_info
    Staff.includes(:staff_type, :employment_type).each_with_object({}) do |s, h|
      h[s.name] = {
        staff_type: s.staff_type.name,
        employment_type: s.employment_type.name,
        unavailable_wdays: s.unavailable_wdays_array
      }
    end
  end

  def build_rules
    staff_type_names = StaffType.pluck(:id, :name).to_h
    PlacementRule.includes(:staff_type, :employment_type).filter_map do |rule|
      case rule.rule_type
      when "min_count"
        { type: "min_count", staff_type: rule.staff_type.name,
          employment_type: rule.employment_type&.name, min: rule.min_count }
      when "at_least_one_of"
        names = rule.staff_type_ids_array.filter_map { |id| staff_type_names[id] }
        { type: "at_least_one_of", staff_types: names }
      when "team_min"
        names = rule.staff_type_ids_array.filter_map { |id| staff_type_names[id] }
        { type: "team_min", staff_types: names, min: rule.min_count }
      end
    end
  end

  def fix_day(day_shifts, exclude_name: nil)
    working = day_shifts.select { |s| s[:is_working] }
    resting = day_shifts.reject { |s| s[:is_working] }
    resting = resting.reject { |s| s[:staff_name] == exclude_name } if exclude_name

    # 配置ルールを満たすよう補完
    @rules.each do |rule|
      case rule[:type]
      when "min_count"
        count = working.count { |s| matches_min_count?(s, rule) }
        if count < rule[:min]
          add_staff(resting, working, rule[:min] - count) { |s| matches_min_count?(s, rule) }
        end
      when "at_least_one_of"
        unless working.any? { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) }
          add_staff(resting, working, 1) { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) }
        end
      when "team_min"
        count = working.count { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) }
        if count < rule[:min]
          add_staff(resting, working, rule[:min] - count) { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) }
        end
      end
    end

    # 最低出勤人数（12人）を満たすよう補完
    if working.size < TotalCountValidator::MIN_STAFF_COUNT
      add_staff(resting, working, TotalCountValidator::MIN_STAFF_COUNT - working.size) { true }
    end

    # ManagerPresenceValidator の条件を満たすよう補完
    manager_present = working.any? do |s|
      info = @staff_info[s[:staff_name]]
      info && (info[:staff_type] == "副館長" ||
               info[:staff_type] == "行政職" ||
               (info[:staff_type] == "一般事務" && info[:employment_type] == "会計年度任用職員"))
    end
    unless manager_present
      add_staff(resting, working, 1) do |s|
        info = @staff_info[s[:staff_name]]
        info && (info[:staff_type] == "副館長" ||
                 info[:staff_type] == "行政職" ||
                 (info[:staff_type] == "一般事務" && info[:employment_type] == "会計年度任用職員"))
      end
    end
  end

  def fix_closed_days
    @shifts.each do |shift|
      shift[:is_working] = false if @closed_days.key?(shift[:date])
    end
  end

  def fix_special_dates
    # 全員出勤日：希望休を除く全職員を出勤にする（閉館日は除く）
    @all_staff_dates.each do |date|
      next if @closed_days.key?(date)
      @shifts.select { |s| s[:date] == date }.each do |shift|
        shift[:is_working] = true unless @leave_set.include?([shift[:staff_name], date])
      end
    end
    # 指定職員出勤日：指定された職員を出勤にする（閉館日でも適用）
    @designated_dates.each do |date, staff_names|
      @shifts.select { |s| s[:date] == date && staff_names.include?(s[:staff_name]) }.each do |shift|
        shift[:is_working] = true unless @leave_set.include?([shift[:staff_name], date])
      end
    end
  end

  def fix_assignment_dates
    @assignment_dates.each do |date, staff_names|
      next if @closed_days.key?(date)
      @shifts.select { |s| s[:date] == date && staff_names.include?(s[:staff_name]) }.each do |shift|
        shift[:is_working] = true unless @leave_set.include?([shift[:staff_name], date])
      end
    end
  end

  def assignment_protected?(staff_name, date)
    return false if @leave_set.include?([staff_name, date])
    @assignment_dates[date]&.include?(staff_name) || @designated_dates[date]&.include?(staff_name)
  end

  def fix_excess_staff
    total_staff_count = @shifts.map { |s| s[:staff_name] }.uniq.size
    max_per_day = (total_staff_count * 0.75).ceil

    # 月全体の勤務日数をカウント（日付昇順で処理しながら更新）
    monthly_work_days = Hash.new(0)
    @shifts.each { |s| monthly_work_days[s[:staff_name]] += 1 if s[:is_working] }

    @shifts.group_by { |s| s[:date] }.sort.each do |date, day_shifts|
      next if @closed_days.key?(date)
      next if @all_staff_dates.include?(date)  # 全員出勤日は削減しない
      working = day_shifts.select { |s| s[:is_working] }
      next if working.size <= max_per_day

      excess = working.size - max_per_day
      # 優先削減順：目標超過 → 不可曜日 → 勤務日数多い（担当会議日は保護）
      candidates = working
        .reject { |s| essential_for_rules?(s, working) }
        .reject { |s| assignment_protected?(s[:staff_name], s[:date]) }
        .sort_by { |s|
          wdays = @staff_info.dig(s[:staff_name], :unavailable_wdays) || []
          unavailable = wdays.include?(s[:date].wday) ? 0 : 1
          target = @staff_target_days[s[:staff_name]] || 0
          over_target = monthly_work_days[s[:staff_name]] > target ? 0 : 1
          [over_target, unavailable, -monthly_work_days[s[:staff_name]]]
        }
      candidates.first([excess, candidates.size].min).each do |shift|
        shift[:is_working] = false
        monthly_work_days[shift[:staff_name]] -= 1
      end
    end
  end

  def fix_weekend_consecutive
    by_staff = @shifts.group_by { |s| s[:staff_name] }
    by_staff.each do |staff_name, staff_shifts|
      shifts_by_date = staff_shifts.each_with_object({}) { |s, h| h[s[:date]] = s }

      staff_shifts.select { |s| s[:is_working] && s[:date].saturday? }.each do |sat_shift|
        sun_shift = shifts_by_date[sat_shift[:date] + 1]
        next unless sun_shift&.[](:is_working)

        # 土日連続：前の金曜か後の月曜を休みにする（出勤者が多い日を優先、担当会議日は保護）
        friday = sat_shift[:date] - 1
        monday = sat_shift[:date] + 2
        candidates = [friday, monday].filter_map do |date|
          s = shifts_by_date[date]
          s if s&.[](:is_working) && !@leave_set.include?([staff_name, date]) &&
               !@closed_days.key?(date) && !assignment_protected?(staff_name, date)
        end
        next if candidates.empty?

        target = candidates.max_by { |s| @shifts.count { |sh| sh[:date] == s[:date] && sh[:is_working] } }
        target[:is_working] = false
      end
    end
  end

  def fix_consecutive_work
    by_staff = @shifts.group_by { |s| s[:staff_name] }
    by_staff.each do |staff_name, staff_shifts|
      10.times do
        working_dates = staff_shifts.select { |s| s[:is_working] }.map { |s| s[:date] }.sort
        groups = find_consecutive_date_groups(working_dates)
        violation = groups.find { |g| g.size > ConsecutiveWorkValidator::MAX_CONSECUTIVE_DAYS }
        break unless violation

        # 6日目以降で、当日の出勤者が最も多い日を選んで休みにする（担当会議日は保護）
        excess_dates = violation[ConsecutiveWorkValidator::MAX_CONSECUTIVE_DAYS..]
                         .reject { |d| assignment_protected?(staff_name, d) }
        break if excess_dates.empty?
        target_date = excess_dates.max_by { |d| @shifts.count { |s| s[:date] == d && s[:is_working] } }
        target_shift = staff_shifts.find { |s| s[:date] == target_date }
        break unless target_shift

        # 休みにし、その日を即座に別の職員で補完する（本人は補完対象から除く）
        target_shift[:is_working] = false
        unless @closed_days.key?(target_date)
          day_shifts = @shifts.select { |s| s[:date] == target_date }
          fix_day(day_shifts, exclude_name: staff_name)
        end
      end
    end
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

  def essential_for_rules?(shift, working)
    @rules.any? do |rule|
      case rule[:type]
      when "min_count"
        next false unless matches_min_count?(shift, rule)
        current = working.count { |s| matches_min_count?(s, rule) }
        current <= rule[:min]
      when "at_least_one_of"
        next false unless rule[:staff_types].include?(@staff_info.dig(shift[:staff_name], :staff_type))
        working.count { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) } <= 1
      when "team_min"
        next false unless rule[:staff_types].include?(@staff_info.dig(shift[:staff_name], :staff_type))
        current = working.count { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) }
        current <= rule[:min]
      end
    end
  end

  def matches_min_count?(shift, rule)
    info = @staff_info[shift[:staff_name]]
    return false unless info
    return false unless info[:staff_type] == rule[:staff_type]
    rule[:employment_type].nil? || info[:employment_type] == rule[:employment_type]
  end

  def add_staff(resting, working, count, &block)
    candidates = resting.select(&block).reject { |s| @leave_set.include?([s[:staff_name], s[:date]]) }
    # 優先度: 1.連続勤務違反なし×不可曜日でない 2.連続違反なし×不可曜日 3.連続違反あり×不可曜日でない 4.連続違反あり×不可曜日
    safe, risky = candidates.partition { |s| !would_cause_consecutive_violation?(s[:staff_name], s[:date]) }
    preferred_safe, fallback_safe = safe.partition { |s|
      !((@staff_info.dig(s[:staff_name], :unavailable_wdays) || []).include?(s[:date].wday))
    }
    preferred_risky, fallback_risky = risky.partition { |s|
      !((@staff_info.dig(s[:staff_name], :unavailable_wdays) || []).include?(s[:date].wday))
    }
    ordered = preferred_safe + fallback_safe + preferred_risky + fallback_risky
    ordered.first([count, ordered.size].min).each do |shift|
      shift[:is_working] = true
      resting.delete(shift)
      working << shift
    end
  end

  def fix_target_days
    return if @staff_target_days.empty?

    daily_counts = Hash.new(0)
    @shifts.each { |s| daily_counts[s[:date]] += 1 if s[:is_working] }

    # 不足が大きい職員を優先して処理
    by_shortfall = @staff_target_days.filter_map do |name, target|
      actual = @shifts.count { |s| s[:staff_name] == name && s[:is_working] }
      diff = target - actual
      diff > 0 ? [name, diff] : nil
    end.sort_by { |_, diff| -diff }

    by_shortfall.each do |staff_name, shortfall|
      unavailable_wdays = @staff_info.dig(staff_name, :unavailable_wdays) || []
      base_filter = ->(s) {
        s[:staff_name] == staff_name && !s[:is_working] &&
          !@closed_days.key?(s[:date]) && !@leave_set.include?([staff_name, s[:date]])
      }
      # unavailable_wdays の日は後回し（できるだけ出勤しない）
      resting = @shifts.select { |s| base_filter.call(s) && !unavailable_wdays.include?(s[:date].wday) }
                       .sort_by { |s| [daily_counts[s[:date]], s[:date]] } +
               @shifts.select { |s| base_filter.call(s) && unavailable_wdays.include?(s[:date].wday) }
                       .sort_by { |s| [daily_counts[s[:date]], s[:date]] }

      added = 0
      resting.each do |shift|
        break if added >= shortfall
        next if would_cause_consecutive_violation?(staff_name, shift[:date])
        shift[:is_working] = true
        daily_counts[shift[:date]] += 1
        added += 1
      end
      resting.each do |shift|
        break if added >= shortfall
        next if shift[:is_working]
        shift[:is_working] = true
        daily_counts[shift[:date]] += 1
        added += 1
      end
    end
  end

  def fix_excess_days
    return if @staff_target_days.empty?

    monthly_work_days = @shifts.each_with_object(Hash.new(0)) { |s, h| h[s[:staff_name]] += 1 if s[:is_working] }

    # 超過が大きい職員を優先して削減
    by_excess = @staff_target_days.filter_map do |name, target|
      diff = monthly_work_days[name] - target
      diff > 0 ? [name, diff] : nil
    end.sort_by { |_, diff| -diff }

    by_excess.each do |staff_name, excess|
      # 全員出勤日・閉館日を除いた出勤シフトを削減候補にする
      # 優先順：出勤者が多い日 → 削減後の連続休みが短い日（月初偏り防止）
      staff_on = @shifts.select { |s| s[:staff_name] == staff_name && s[:is_working] }
                        .map { |s| s[:date] }.to_set
      working_shifts = @shifts.select { |s|
        s[:staff_name] == staff_name && s[:is_working] &&
          !@closed_days.key?(s[:date]) && !@all_staff_dates.include?(s[:date]) &&
          !@leave_set.include?([staff_name, s[:date]]) &&
          !assignment_protected?(staff_name, s[:date])
      }.sort_by { |s|
        day_count = @shifts.count { |sh| sh[:date] == s[:date] && sh[:is_working] }
        d = s[:date] - 1
        pre = 0
        while d >= s[:date].beginning_of_month && !staff_on.include?(d) && !@closed_days.key?(d)
          pre += 1; d -= 1
        end
        d = s[:date] + 1
        post = 0
        while d <= s[:date].end_of_month && !staff_on.include?(d) && !@closed_days.key?(d)
          post += 1; d += 1
        end
        [-day_count, pre + post + 1]
      }

      removed = 0
      working_shifts.each do |shift|
        break if removed >= excess
        day_shifts = @shifts.select { |s| s[:date] == shift[:date] }
        working = day_shifts.select { |s| s[:is_working] }
        next if working.size <= TotalCountValidator::MIN_STAFF_COUNT
        next if essential_for_rules?(shift, working)
        shift[:is_working] = false
        monthly_work_days[staff_name] -= 1
        removed += 1
      end
    end
  end

  def would_cause_consecutive_violation?(staff_name, date)
    staff_shifts = @shifts.select { |s| s[:staff_name] == staff_name }
    working_dates = staff_shifts.select { |s| s[:is_working] }.map { |s| s[:date] }.sort
    test_dates = (working_dates + [date]).uniq.sort
    groups = find_consecutive_date_groups(test_dates)
    groups.any? { |g| g.size > ConsecutiveWorkValidator::MAX_CONSECUTIVE_DAYS }
  end
end
