class ShiftPostProcessor
  def initialize(parsed_shifts, closed_days, leave_requests = [], special_dates = [], staff_target_days = {}, assignment_constraints = [], mobile_library_constraints = [], weekend_consecutive_debt = {})
    @shifts = parsed_shifts
    @closed_days = closed_days
    @staff_target_days = staff_target_days
    # 今年度これまでの「土日連続休み回数 − 土日連続勤務回数」。値が大きい
    # 職員ほど、次に土日連続勤務が避けられない場面で割り当てるのが公平。
    # 値が小さい（既に多く土日連続勤務をこなした）職員ほど優先して救済する
    @weekend_consecutive_debt = weekend_consecutive_debt
    @leave_set = leave_requests.each_with_object(Set.new) do |lr, set|
      set << [lr[:staff_name], Date.parse(lr[:date])]
    end
    @all_staff_dates = special_dates.each_with_object(Set.new) do |sd, set|
      set << Date.parse(sd[:date]) if sd[:target_group] == "全職員"
    end
    @designated_dates = special_dates.each_with_object(Hash.new { |h, k| h[k] = [] }) do |sd, h|
      next if sd[:designated_staffs].empty?
      h[Date.parse(sd[:date])].concat(sd[:designated_staffs])
    end
    # target_group が職種名（全職員以外）のスケジュール: {date => [group_name, ...]}
    # designated_staffs が同時に設定されていてもグループ全員を保護する
    @group_dates = special_dates.each_with_object(Hash.new { |h, k| h[k] = [] }) do |sd, h|
      next if sd[:target_group] == "全職員"
      next if sd[:target_group].blank?
      h[Date.parse(sd[:date])] << sd[:target_group]
    end
    # 担当会議日: {date => [staff_name, ...]}
    @assignment_dates = assignment_constraints.each_with_object({}) do |ac, h|
      ac[:dates].each do |date_str|
        date = Date.parse(date_str)
        h[date] ||= []
        h[date].concat(ac[:staff_names])
      end
    end
    # 移動図書館巡回日: {date => [staff_name, ...]}
    @mobile_dates = (mobile_library_constraints || []).each_with_object({}) do |ml, h|
      date = Date.parse(ml[:date])
      h[date] ||= []
      h[date].concat(ml[:staff_names])
    end
    # DutyAssigner等、本処理の後段で確定する保護日（祝日ポスト当番など）を
    # reconcile_weekend_consecutive! 実行前に register_protected_dates で追加する
    @extra_protected_dates = Set.new
    # 土日連続回避のために「休みにする」と決めた[staff_name, date]。
    # 希望休と同様に、以降の補充処理（add_staff/fix_target_days）が
    # 勝手に出勤へ戻せないようロックする
    @locked_rest_days = Set.new
    @staff_info = build_staff_info
    @rules = build_rules
    # 1日の最低出勤人数は「複数職種の合計最低出勤人数」（team_min）の配置ルールで
    # 管理者が設定する値のみを根拠とする（固定値は持たない）
    @min_staff_count = @rules.select { |r| r[:type] == "team_min" }.filter_map { |r| r[:min] }.max || 0
  end

  def process
    fix_closed_days
    fix_leave_requests
    fix_special_dates
    fix_assignment_dates
    fix_mobile_library_dates
    fix_excess_staff
    5.times do
      snapshot = @shifts.map { |s| s[:is_working] }
      # fix_day（最低出勤人数・配置ルールの補充）が週の上限超過・土日連続を
      # 新たに作ることがあるため、毎回ループの先頭でチェックし直す
      fix_regular_weekly_pattern
      fix_hourly_weekend_balance
      fix_weekly_overwork
      pay_down_weekend_consecutive_debt
      fix_weekend_consecutive
      fix_weekend_consecutive_monthly_cap
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

  # DutyAssigner による祝日ポスト当番などの後段割当は本処理の後に実行されるため、
  # その割当で新たに生じた土日連続出勤に対応するには process 完了後にこちらを呼ぶ。
  # duty_protected_pairs: [[staff_name, date], ...]（当該日は保護日として扱う）
  def reconcile_weekend_consecutive!(duty_protected_pairs = [])
    register_protected_dates(duty_protected_pairs)
    # fix_dayの補充が週上限超過・土日連続を新たに作ることがあるため、
    # process()と同様に複数回チェックし直す
    3.times do
      snapshot = @shifts.map { |s| s[:is_working] }
      fix_weekly_overwork
      # ここが最終チェックのため、回避を試みても後続のfix_dayで打ち消されると
      # 手が無くなる。素直に月曜代休で決着させる
      fix_weekend_consecutive(prefer_cancel: false)
      fix_weekend_consecutive_monthly_cap
      @shifts.group_by { |s| s[:date] }.each do |date, day_shifts|
        next if @closed_days.key?(date)
        fix_day(day_shifts)
      end
      break if @shifts.map { |s| s[:is_working] } == snapshot
    end
    @shifts
  end

  def register_protected_dates(pairs)
    pairs.each { |staff_name, date| @extra_protected_dates << [staff_name, date] }
  end

  private

  def build_staff_info
    Staff.includes(:staff_type, :employment_type).each_with_object({}) do |s, h|
      h[s.name] = {
        staff_type: s.staff_type.name,
        employment_type: s.employment_type.name,
        unavailable_wdays: s.unavailable_wdays_array,
        weekly_work_days: s.weekly_work_days,
        is_regular: s.employment_type.is_regular
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
        names = rule.staff_type_ids_array.filter_map { |id| staff_type_names[id.to_i] }
        { type: "at_least_one_of", staff_types: names }
      when "team_min"
        names = rule.staff_type_ids_array.filter_map { |id| staff_type_names[id.to_i] }
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
  end

  def fix_closed_days
    @shifts.each do |shift|
      shift[:is_working] = false if @closed_days.key?(shift[:date])
    end
  end

  def fix_leave_requests
    @shifts.each do |shift|
      shift[:is_working] = false if @leave_set.include?([shift[:staff_name], shift[:date]])
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
    # グループ指定出勤日：該当職種の職員を出勤にする
    @group_dates.each do |date, group_names|
      next if @closed_days.key?(date)
      @shifts.select { |s| s[:date] == date }.each do |shift|
        info = @staff_info[shift[:staff_name]]
        next unless info && group_names.include?(info[:staff_type])
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

  def fix_mobile_library_dates
    @mobile_dates.each do |date, staff_names|
      next if @closed_days.key?(date)
      @shifts.select { |s| s[:date] == date && staff_names.include?(s[:staff_name]) }.each do |shift|
        shift[:is_working] = true unless @leave_set.include?([shift[:staff_name], date])
      end
    end
  end

  def assignment_protected?(staff_name, date)
    return false if @leave_set.include?([staff_name, date])
    return true if @all_staff_dates.include?(date)
    return true if @extra_protected_dates.include?([staff_name, date])
    return true if @assignment_dates[date]&.include?(staff_name)
    return true if @designated_dates[date]&.include?(staff_name)
    return true if @mobile_dates[date]&.include?(staff_name)
    if @group_dates[date]&.any?
      info = @staff_info[staff_name]
      return true if info && @group_dates[date].include?(info[:staff_type])
    end
    false
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

  REGULAR_FIXED_WDAYS = [1, 3, 4, 5].freeze # 月・水・木・金
  # 配置ルール上「どちらかがいればいい」関係にある職種は、土日の均等配分でも
  # 同じグループとして扱う（副館長・行政職・一般事務はteam_minルールで
  # 合計1名以上いればよく、同じ枠を共有するため。館長はこのルールに含まれない）
  WEEKEND_GROUP_OVERRIDES = { "副館長" => "配置ルール共有枠", "行政職" => "配置ルール共有枠", "一般事務" => "配置ルール共有枠" }.freeze

  def weekend_group_key(staff_name)
    staff_type = @staff_info.dig(staff_name, :staff_type)
    WEEKEND_GROUP_OVERRIDES[staff_type] || staff_type
  end

  # 正規職員は月・水・木・金を基本的に出勤とし、土日はどちらか1日だけ出勤する
  # （火曜定休日＋土日どちらか1日の週2日休み）。この形が崩れている場合に補正する
  def fix_regular_weekly_pattern
    regular_names = @staff_info.select { |_, info| info[:is_regular] }.keys
    by_staff = @shifts.group_by { |s| s[:staff_name] }

    # 月・水・木・金は基本的に出勤させる
    regular_names.shuffle.each do |staff_name|
      staff_shifts = by_staff[staff_name] || []
      unavailable_wdays = @staff_info.dig(staff_name, :unavailable_wdays) || []
      staff_shifts.each do |shift|
        next unless REGULAR_FIXED_WDAYS.include?(shift[:date].wday)
        next if shift[:is_working]
        next if unavailable_wdays.include?(shift[:date].wday)
        next if fixed_and_unmovable?(staff_name, shift[:date])
        next if would_cause_consecutive_violation?(staff_name, shift[:date])
        shift[:is_working] = true
      end
    end

    # 土日は「どちらかがいればいい」職種グループ単位で、できるだけ半数ずつ
    # 土曜・日曜に振り分ける（例：正規司書4人なら2人ずつ）。これにより
    # 配置ルールの必要人数をグループ内で自然に満たし、後段の補充が
    # 特定の職員に土日連続出勤を強いることを防ぐ
    #
    # ただし土日のどちらかが全員出勤日の場合は「必ずどちらか片方だけ」という
    # 前提が崩れる（全員出勤日は動かせないため）。この場合、何もしないと
    # もう一方の日は正規職員全員が休みになり、その穴を会計年度任用職員だけで
    # 埋めることになって偏りが生じる。そのため正規職員全体で、もう一方の日に
    # おおよそ半数が出勤する形に均す（配置ルールに必要な人は対象から除外する
    # ため、配置ルールを満たさなくなることはない。不足分は後段のfix_dayが補充する）
    by_group = regular_names.group_by { |name| weekend_group_key(name) }
    @shifts.select { |s| s[:date].saturday? }.map { |s| s[:date] }.uniq.sort.each do |sat|
      sun = sat + 1
      next unless @shifts.any? { |s| s[:date] == sun }

      if @all_staff_dates.include?(sat) ^ @all_staff_dates.include?(sun)
        movable = @all_staff_dates.include?(sat) ? sun : sat
        balance_weekend_half(regular_names, movable)
      else
        by_group.each_value { |names| assign_weekend_group(names, sat, sun) }
      end
    end
  end

  # 土日のどちらかが全員出勤日になっている週について、会計年度任用職員側も
  # もう一方の日におおよそ半数が出勤する形に均す（正規職員側は
  # fix_regular_weekly_pattern 内で balance_weekend_half により対応済み）
  def fix_hourly_weekend_balance
    hourly_names = @staff_info.reject { |_, info| info[:is_regular] }.keys
    @shifts.select { |s| s[:date].saturday? }.map { |s| s[:date] }.uniq.sort.each do |sat|
      sun = sat + 1
      next unless @shifts.any? { |s| s[:date] == sun }
      next unless @all_staff_dates.include?(sat) ^ @all_staff_dates.include?(sun)

      movable = @all_staff_dates.include?(sat) ? sun : sat
      balance_weekend_half(hourly_names, movable)
    end
  end

  # 指定した職員グループについて、movable_date（全員出勤日の対になる方の
  # 土日）の出勤者数をグループの半数程度に近づける。配置ルール上どうしても
  # 必要な人（essential_for_rules?）は休み候補から除外するため、この調整で
  # 配置ルールが満たせなくなることはない。全員出勤日は動かせないため、
  # 選ばれた半数は結果的に土日連続出勤になるが、これはユーザーの要望どおり
  # 許容する（その分、週の上限を超えないよう平日側で調整する）
  def balance_weekend_half(names, movable_date)
    pairs = names.filter_map do |name|
      shift = @shifts.find { |s| s[:staff_name] == name && s[:date] == movable_date }
      [name, shift] if shift
    end
    return if pairs.empty?

    target = (pairs.size / 2.0).round
    working, resting = pairs.partition { |_, s| s[:is_working] }
    day_working = @shifts.select { |s| s[:date] == movable_date && s[:is_working] }

    if working.size > target
      excess = working.size - target
      # weekend_consecutive_debt が小さい（＝既に土日連続勤務を多くこなして
      # いる）職員から優先して救済（休みに）する
      candidates = working.sort_by { |name, _| @weekend_consecutive_debt[name] || 0 }.reject { |name, s|
        fixed_and_unmovable?(name, s[:date]) || would_drop_below_minimum?(s[:date]) || essential_for_rules?(s, day_working)
      }
      candidates.first(excess).each { |name, s| lock_rest_day(s, name) }
    elsif working.size < target
      shortfall = target - working.size
      # weekend_consecutive_debt が大きい（＝土日連続休みを多く取っている割に
      # 土日連続勤務が少ない）職員から優先して今回の土日連続勤務に割り当てる
      candidates = resting.sort_by { |name, _| -(@weekend_consecutive_debt[name] || 0) }.reject { |name, s| fixed_and_unmovable?(name, s[:date]) || would_cause_consecutive_violation?(name, s[:date]) }
      candidates.first(shortfall).each do |name, s|
        s[:is_working] = true
        make_room_for_weekly_cap(name, s[:date])
        # fix_weekly_overwork等の後続処理（reconcile_weekend_consecutive!内も
        # 含む）がこの意図的な出勤を「超過」とみなして打ち消してしまわない
        # よう、保護日として確定させる
        @extra_protected_dates << [name, s[:date]]
      end
    end
  end

  # 週の上限を超えないよう、必要なら同じ週の平日出勤を1日分キャンセルする。
  # 何もしないと後段の fix_weekly_overwork が土日を優先してキャンセルして
  # しまい、balance_weekend_half でせっかく割り当てた出勤が打ち消される
  def make_room_for_weekly_cap(staff_name, date)
    cap = @staff_info.dig(staff_name, :weekly_work_days)
    return unless cap

    week_shifts = @shifts.select { |s| s[:staff_name] == staff_name && s[:date].beginning_of_week == date.beginning_of_week }
    working = week_shifts.select { |s| s[:is_working] }
    excess = working.size - cap
    return if excess <= 0

    candidates = working
      .reject { |s| s[:date].saturday? || s[:date].sunday? }
      .reject { |s| @leave_set.include?([staff_name, s[:date]]) }
      .reject { |s| assignment_protected?(staff_name, s[:date]) }

    candidates.first(excess).each { |s| cancel_and_backfill(s, staff_name) }
  end

  def assign_weekend_group(names, sat, sun)
    by_staff = @shifts.group_by { |s| s[:staff_name] }
    pairs = names.filter_map do |name|
      sat_shift = by_staff[name]&.find { |s| s[:date] == sat }
      sun_shift = by_staff[name]&.find { |s| s[:date] == sun }
      [name, sat_shift, sun_shift] if sat_shift && sun_shift
    end

    # 1. 土日とも出勤になっている人がいれば、動かせる方を休みにする
    #    （グループ内の均等配分をこの後の手順で成立させるための下準備）。
    #    weekend_consecutive_debt が小さい（＝既に土日連続勤務を多くこなして
    #    いる）職員を優先して処理することで、最低人数等の制約で全員には
    #    休みを割り当てられない場合でも、土日連続勤務が多い職員から
    #    優先的に休みを割り当てる
    pairs.sort_by { |name, *| @weekend_consecutive_debt[name] || 0 }.each do |name, sat_shift, sun_shift|
      next unless sat_shift[:is_working] && sun_shift[:is_working]

      cancel_candidates = [sat_shift, sun_shift].reject do |s|
        fixed_and_unmovable?(name, s[:date]) || would_drop_below_minimum?(s[:date])
      end
      next if cancel_candidates.empty?

      target = cancel_candidates.max_by { |s| @shifts.count { |sh| sh[:date] == s[:date] && sh[:is_working] } }
      lock_rest_day(target, name)
    end

    # 2. 土日とも休みのままの人を、出勤者が少ない方に順番に割り当てて均等化する
    sat_count = pairs.count { |_, s, _| s[:is_working] }
    sun_count = pairs.count { |_, _, s| s[:is_working] }

    undecided = pairs.shuffle.select { |_, s, u| !s[:is_working] && !u[:is_working] }
    undecided.each do |name, sat_shift, sun_shift|
      use_sat = sat_count <= sun_count
      target_shift = use_sat ? sat_shift : sun_shift
      other_shift = use_sat ? sun_shift : sat_shift

      if !fixed_and_unmovable?(name, target_shift[:date]) &&
         !would_cause_consecutive_violation?(name, target_shift[:date])
        target_shift[:is_working] = true
        use_sat ? sat_count += 1 : sun_count += 1
      elsif !fixed_and_unmovable?(name, other_shift[:date]) &&
            !would_cause_consecutive_violation?(name, other_shift[:date])
        other_shift[:is_working] = true
        use_sat ? sun_count += 1 : sat_count += 1
      end
    end
  end

  # 希望休・閉館日・ロック済みの休み・全員出勤日やスケジュール等の
  # 保護指定など、動かせない日かどうか
  def fixed_and_unmovable?(staff_name, date)
    @closed_days.key?(date) ||
      @leave_set.include?([staff_name, date]) ||
      @locked_rest_days.include?([staff_name, date]) ||
      assignment_protected?(staff_name, date)
  end

  # 職員ごとの週勤務日数（weekly_work_days）の上限を超えている週があれば、
  # 超過分を休みにする。土日を優先して休みにすることで、
  # 「ある週は土日とも出勤、別の週は少なめ」という偏りと土日連続出勤の
  # 両方を根本から抑える
  def fix_weekly_overwork
    by_staff = @shifts.group_by { |s| s[:staff_name] }
    by_staff.to_a.shuffle.each do |staff_name, staff_shifts|
      cap = @staff_info.dig(staff_name, :weekly_work_days)
      next unless cap

      staff_shifts.group_by { |s| s[:date].beginning_of_week }.each_value do |week_shifts|
        working = week_shifts.select { |s| s[:is_working] }
        excess = working.size - cap
        next if excess <= 0

        candidates = working
          .reject { |s| @leave_set.include?([staff_name, s[:date]]) }
          .reject { |s| assignment_protected?(staff_name, s[:date]) }
          .reject { |s| would_drop_below_minimum?(s[:date]) }
          .sort_by { |s| s[:date].saturday? || s[:date].sunday? ? 0 : 1 }

        candidates.first(excess).each { |s| lock_rest_day(s, staff_name) }
      end
    end
  end

  # 土日連続休みの負債（weekend_consecutive_debt > 0）が残っている職員は、
  # 通常の処理では「たまたま土日連続勤務になった場合に救済されにくい」という
  # 受動的な優先度しか持たず、その機会自体が発生しなければ負債はいつまでも
  # 解消されない。そのため、負債がある職員については、
  # fix_weekend_consecutive_monthly_capと同じ上限（月2回）に達するまで、
  # 積極的に土日連続勤務を作る。ここで作った分は @extra_protected_dates で
  # 保護し、fix_weekend_consecutive が「保護なしの土日連続」として
  # 打ち消してしまわないようにする（保護済みのため、片方をキャンセルする
  # のではなく月曜代休で決着する通常の扱いになる）
  PAYOFF_TARGET_OCCURRENCES = 2

  def pay_down_weekend_consecutive_debt
    by_staff = @shifts.group_by { |s| s[:staff_name] }
    # 負債が大きい職員から順に機会を与える（枠の奪い合いになった場合の公平性）
    by_staff.to_a.sort_by { |name, _| -(@weekend_consecutive_debt[name] || 0) }.each do |staff_name, staff_shifts|
      next unless (@weekend_consecutive_debt[staff_name] || 0) > 0

      shifts_by_date = staff_shifts.each_with_object({}) { |s, h| h[s[:date]] = s }
      saturdays = staff_shifts.select { |s| s[:date].saturday? }.sort_by { |s| s[:date] }
      existing = saturdays.count { |sat| sat[:is_working] && shifts_by_date[sat[:date] + 1]&.[](:is_working) }
      needed = PAYOFF_TARGET_OCCURRENCES - existing
      next if needed <= 0

      unavailable_wdays = @staff_info.dig(staff_name, :unavailable_wdays) || []

      saturdays.each do |sat_shift|
        break if needed <= 0
        sun_shift = shifts_by_date[sat_shift[:date] + 1]
        next unless sun_shift
        next if sat_shift[:is_working] && sun_shift[:is_working] # 既に土日連続済みの週末は対象外
        # 全員出勤日とペアの週末は balance_weekend_half が担当するため対象外
        next if @all_staff_dates.include?(sat_shift[:date]) ^ @all_staff_dates.include?(sun_shift[:date])
        next if unavailable_wdays.include?(0) || unavailable_wdays.include?(6)

        targets = [sat_shift, sun_shift].reject { |s| s[:is_working] }
        next if targets.empty?
        next if targets.any? { |s| @leave_set.include?([staff_name, s[:date]]) || @closed_days.key?(s[:date]) }

        staff_working_dates = staff_shifts.select { |s| s[:is_working] }.map { |s| s[:date] }
        test_dates = (staff_working_dates + targets.map { |s| s[:date] }).uniq.sort
        groups = find_consecutive_date_groups(test_dates)
        next if groups.any? { |g| g.size > ConsecutiveWorkValidator::MAX_CONSECUTIVE_DAYS }

        targets.each { |s| s[:is_working] = true }
        targets.each { |s| make_room_for_weekly_cap(staff_name, s[:date]) }
        targets.each { |s| @extra_protected_dates << [staff_name, s[:date]] }
        needed -= 1
      end
    end
  end

  # prefer_cancel: true の場合、保護理由のない土日連続はまず片方をキャンセルして
  # 回避を試みる。false の場合は回避を試みず、常に月曜代休で決着させる
  # （後段のfix_dayが埋め直せなくなった最終チェック用）
  def fix_weekend_consecutive(prefer_cancel: true)
    by_staff = @shifts.group_by { |s| s[:staff_name] }
    # 最低出勤人数の制約で「休みにできる枠」が全員分は無い月・週もあるため、
    # 常に同じ並び順（職員のsort_order）で処理すると枠を使い切れる職員が固定化し、
    # 特定の職員に土日連続出勤が偏ってしまう。weekend_consecutive_debt が
    # 小さい（＝既に土日連続勤務を多くこなしている）職員から優先して処理し、
    # 全員は救済しきれない場合でも土日連続勤務が多い職員から優先的に
    # 休みを割り当てる
    by_staff.to_a.sort_by { |staff_name, _| @weekend_consecutive_debt[staff_name] || 0 }.each do |staff_name, staff_shifts|
      shifts_by_date = staff_shifts.each_with_object({}) { |s, h| h[s[:date]] = s }

      staff_shifts.select { |s| s[:is_working] && s[:date].saturday? }.sort_by { |s| s[:date] }.each do |sat_shift|
        sun_shift = shifts_by_date[sat_shift[:date] + 1]
        next unless sun_shift&.[](:is_working)
        # 土日のどちらかが全員出勤日の場合は、balance_weekend_half /
        # fix_hourly_weekend_balance が「意図的におおよそ半数を土日連続にする」
        # 調整を担当するため、ここで保護なし扱いにして打ち消してしまわないよう
        # 何もしない（両方とも全員出勤の場合は従来どおり月曜代休で対応する）
        next if @all_staff_dates.include?(sat_shift[:date]) ^ @all_staff_dates.include?(sun_shift[:date])

        sat_protected = assignment_protected?(staff_name, sat_shift[:date])
        sun_protected = assignment_protected?(staff_name, sun_shift[:date])

        if sat_protected && sun_protected
          # 両方とも保護されている場合 → 本人の週末は動かせないため月曜を休みにする
          give_weekend_consecutive_makeup(staff_name, sat_shift[:date], shifts_by_date)
        elsif sat_protected ^ sun_protected
          # 片方だけ保護されている場合 → 保護されていない方を休みにする（最低人数は割らない）
          unprotected = sun_protected ? sat_shift : sun_shift
          if !@leave_set.include?([staff_name, unprotected[:date]]) && !would_drop_below_minimum?(unprotected[:date])
            lock_rest_day(unprotected, staff_name)
          else
            give_weekend_consecutive_makeup(staff_name, sat_shift[:date], shifts_by_date)
          end
        elsif prefer_cancel
          # 両方とも保護なし（基本ケース）→ 土日のどちらかを休みにして連続出勤自体を回避する。
          # 出勤者が多い方（＝他の職員で埋め合わせしやすい方）を優先して休みにするが、
          # 最低出勤人数を割り込む日は候補から外し、特定の日に休みが集中しないようにする。
          cancel_candidates = [sat_shift, sun_shift]
            .reject { |s| @leave_set.include?([staff_name, s[:date]]) }
            .reject { |s| would_drop_below_minimum?(s[:date]) }
          if cancel_candidates.any?
            target = cancel_candidates.max_by { |s| @shifts.count { |sh| sh[:date] == s[:date] && sh[:is_working] } }
            lock_rest_day(target, staff_name)
          else
            # 両日とも動かせない（希望休 or 最低人数維持のため）場合は月曜を休みにする
            give_weekend_consecutive_makeup(staff_name, sat_shift[:date], shifts_by_date)
          end
        else
          give_weekend_consecutive_makeup(staff_name, sat_shift[:date], shifts_by_date)
        end
      end
    end
  end

  # 職員ごとに、当月の土日連続勤務の回数が上限を超えないようにする。
  # 上限は通常1回。ただし土日連続休みの負債（weekend_consecutive_debt）が
  # 残っている職員は、その分を今月以降の土日連続勤務で引き受けてもらう
  # ため2回まで許容する（3回以上にはしない：一度に大きく負担を偏らせず、
  # 負債が多い場合は複数月にわたって少しずつ解消する）。
  # fix_weekend_consecutive / balance_weekend_half 等で解消しきれず、
  # 月内に上限を超える回数が残ってしまった場合の最終チェック
  def fix_weekend_consecutive_monthly_cap
    @shifts.group_by { |s| s[:staff_name] }.each do |staff_name, staff_shifts|
      shifts_by_date = staff_shifts.each_with_object({}) { |s, h| h[s[:date]] = s }
      occurrences = staff_shifts.select { |s| s[:is_working] && s[:date].saturday? }.sort_by { |s| s[:date] }
        .select { |sat_shift| shifts_by_date[sat_shift[:date] + 1]&.[](:is_working) }

      cap = (@weekend_consecutive_debt[staff_name] || 0) > 0 ? 2 : 1
      excess = occurrences.size - cap
      next if excess <= 0

      occurrences.each do |sat_shift|
        break if excess <= 0
        sun_shift = shifts_by_date[sat_shift[:date] + 1]
        next unless sat_shift[:is_working] && sun_shift[:is_working]
        # 全員出勤日とペアになる週末は balance_weekend_half が管理しているため
        # 対象外にする
        next if @all_staff_dates.include?(sat_shift[:date]) ^ @all_staff_dates.include?(sun_shift[:date])

        sat_protected = assignment_protected?(staff_name, sat_shift[:date])
        sun_protected = assignment_protected?(staff_name, sun_shift[:date])
        next if sat_protected && sun_protected

        target = sun_protected ? sat_shift : sun_shift
        next if @leave_set.include?([staff_name, target[:date]])
        day_working = @shifts.select { |s| s[:date] == target[:date] && s[:is_working] }
        next if essential_for_narrow_rules?(target, day_working)

        cancel_and_backfill(target, staff_name)
        excess -= 1 unless sat_shift[:is_working] && sun_shift[:is_working]
      end
    end
  end

  def lock_rest_day(shift, staff_name)
    shift[:is_working] = false
    @locked_rest_days << [staff_name, shift[:date]]
  end

  # 指定シフトを休みにし、その日を即座に別の職員で補完する（本人は補完対象から除く）。
  # 最低出勤人数ちょうどの日でも、キャンセルと補完をセットで行うことで
  # 「最低人数を割るから動かせない」まま身動きが取れなくなるのを防ぐ
  # （fix_consecutive_workの補完処理と同じパターン）。
  # ただし代わりの人が見つからず出勤人数が元より減ってしまう場合は、
  # その日を悪化させないよう元に戻す（配置ルール違反という目に見える形の
  # 悪化を新たに生まないことを優先する）
  def cancel_and_backfill(shift, staff_name)
    date = shift[:date]
    before_count = @shifts.count { |s| s[:date] == date && s[:is_working] }
    lock_rest_day(shift, staff_name)
    unless @closed_days.key?(date)
      day_shifts = @shifts.select { |s| s[:date] == date }
      fix_day(day_shifts, exclude_name: staff_name)
    end

    after_count = @shifts.count { |s| s[:date] == date && s[:is_working] }
    return if after_count >= before_count

    shift[:is_working] = true
    @locked_rest_days.delete([staff_name, date])
  end

  def would_drop_below_minimum?(date)
    @shifts.count { |s| s[:date] == date && s[:is_working] } <= @min_staff_count
  end

  # 土日連続出勤の代休はまず翌月曜を休みにする。月曜が動かせない、または
  # 代わりが見つからず解消できない場合は、前の金曜を休みにする
  def give_weekend_consecutive_makeup(staff_name, sat_date, shifts_by_date)
    monday = sat_date + 2
    return if try_weekend_makeup_day(staff_name, monday, shifts_by_date)

    friday = sat_date - 1
    try_weekend_makeup_day(staff_name, friday, shifts_by_date)
  end

  # 指定日を休みにできれば休みにして true を返す。希望休・休館日・保護日は
  # 対象外。配置ルール上その人がいないと最低人数を満たせない
  # （essential_for_rules?）場合も対象外にする。cancel_and_backfillの
  # 「元より人数が減ったら元に戻す」判定は日全体の人数しか見ておらず、
  # 他の職種の人数に余裕があると「特定の配置ルール（例：副館長・行政職・
  # 一般事務の最低1人）だけ満たせなくなる」ケースを検知できないため
  def try_weekend_makeup_day(staff_name, date, shifts_by_date)
    shift = shifts_by_date[date]
    return false unless shift&.[](:is_working) &&
                         !@leave_set.include?([staff_name, date]) &&
                         !@closed_days.key?(date) &&
                         !assignment_protected?(staff_name, date)

    day_working = @shifts.select { |s| s[:date] == date && s[:is_working] }
    return false if essential_for_narrow_rules?(shift, day_working)

    cancel_and_backfill(shift, staff_name)
    !shift[:is_working]
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
    @rules.any? { |rule| essential_for_rule?(shift, working, rule) }
  end

  # essential_for_rules? のうち、全職種を対象とするteam_minルール（＝実質的に
  # 1日の総出勤人数の下限と同義）を除外した版。cancel_and_backfillは
  # キャンセル直後に即座に別の職員で埋め直し、埋め直せなければ自動的に
  # 元に戻す（人数ベースでの安全策）ため、総人数と同義のルールを重ねて
  # ここでブロックしてしまうと、代わりが実際にはいるのに試す前に諦めて
  # しまう（例：ちょうど最低人数の日は全員が「必須」扱いになり、
  # 土日連続勤務の是正が一切できなくなる）。職種を絞った、より狭い
  # ルール（配置ルール上その職種の人がいないと満たせないもの）だけを
  # チェックする
  def essential_for_narrow_rules?(shift, working)
    all_staff_types = @staff_info.values.map { |info| info[:staff_type] }.uniq
    @rules.any? do |rule|
      next false if rule[:type] == "team_min" && (all_staff_types - rule[:staff_types]).empty?
      essential_for_rule?(shift, working, rule)
    end
  end

  def essential_for_rule?(shift, working, rule)
    case rule[:type]
    when "min_count"
      return false unless matches_min_count?(shift, rule)
      current = working.count { |s| matches_min_count?(s, rule) }
      current <= rule[:min]
    when "at_least_one_of"
      return false unless rule[:staff_types].include?(@staff_info.dig(shift[:staff_name], :staff_type))
      working.count { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) } <= 1
    when "team_min"
      return false unless rule[:staff_types].include?(@staff_info.dig(shift[:staff_name], :staff_type))
      current = working.count { |s| rule[:staff_types].include?(@staff_info.dig(s[:staff_name], :staff_type)) }
      current <= rule[:min]
    else
      false
    end
  end

  def matches_min_count?(shift, rule)
    info = @staff_info[shift[:staff_name]]
    return false unless info
    return false unless info[:staff_type] == rule[:staff_type]
    rule[:employment_type].nil? || info[:employment_type] == rule[:employment_type]
  end

  # 職員の当月の目標出勤日数に対して、まだどれだけ余裕があるか（残り日数）。
  # 目標を大きく超えている職員ほど小さい（マイナスにもなる）値になる
  def remaining_target_room(staff_name)
    target = @staff_target_days[staff_name]
    return 0 unless target
    current = @shifts.count { |s| s[:staff_name] == staff_name && s[:is_working] }
    target - current
  end

  def add_staff(resting, working, count, &block)
    candidates = resting.select(&block)
      .reject { |s| @leave_set.include?([s[:staff_name], s[:date]]) }
      .reject { |s| @locked_rest_days.include?([s[:staff_name], s[:date]]) }
      # 希望休が少ない等の理由で「いつでも入れる」職員ばかりが配置ルール
      # 補充のたびに選ばれ、目標出勤日数を大きく超過してしまうのを防ぐため、
      # 目標にまだ余裕がある職員を優先する
      .sort_by { |s| -remaining_target_room(s[:staff_name]) }
    # 優先度: 1.連続違反なし×土日連続なし×週上限内×不可曜日でない
    #        2.連続違反なし×土日連続なし×週上限内×不可曜日
    #        3.連続違反なし×土日連続なし×週上限超過 4.連続違反なし×土日連続あり
    #        5.連続違反あり×不可曜日でない 6.連続違反あり×不可曜日
    safe, risky = candidates.partition { |s| !would_cause_consecutive_violation?(s[:staff_name], s[:date]) }
    safe_no_weekend, safe_weekend = safe.partition { |s| !would_cause_weekend_consecutive?(s[:staff_name], s[:date]) }
    safe_no_weekend_no_cap, safe_no_weekend_over_cap = safe_no_weekend.partition { |s|
      !would_exceed_weekly_cap?(s[:staff_name], s[:date])
    }
    preferred_safe, fallback_safe = safe_no_weekend_no_cap.partition { |s|
      !((@staff_info.dig(s[:staff_name], :unavailable_wdays) || []).include?(s[:date].wday))
    }
    preferred_risky, fallback_risky = risky.partition { |s|
      !((@staff_info.dig(s[:staff_name], :unavailable_wdays) || []).include?(s[:date].wday))
    }
    ordered = preferred_safe + fallback_safe + safe_no_weekend_over_cap + safe_weekend + preferred_risky + fallback_risky
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
          !@closed_days.key?(s[:date]) && !@leave_set.include?([staff_name, s[:date]]) &&
          !@locked_rest_days.include?([staff_name, s[:date]])
      }
      # unavailable_wdays の日は後回し（できるだけ出勤しない）
      resting = @shifts.select { |s| base_filter.call(s) && !unavailable_wdays.include?(s[:date].wday) }
                       .sort_by { |s| [daily_counts[s[:date]], s[:date]] } +
               @shifts.select { |s| base_filter.call(s) && unavailable_wdays.include?(s[:date].wday) }
                       .sort_by { |s| [daily_counts[s[:date]], s[:date]] }

      added = 0
      # 優先度1: 5日超え連続にも土日連続にも週上限超過にもならない日
      resting.each do |shift|
        break if added >= shortfall
        next if would_cause_consecutive_violation?(staff_name, shift[:date])
        next if would_cause_weekend_consecutive?(staff_name, shift[:date])
        next if would_exceed_weekly_cap?(staff_name, shift[:date])
        shift[:is_working] = true
        daily_counts[shift[:date]] += 1
        added += 1
      end
      # 優先度2: 5日超え連続にはならず土日連続にもならないが、週上限は超える日
      resting.each do |shift|
        break if added >= shortfall
        next if shift[:is_working]
        next if would_cause_consecutive_violation?(staff_name, shift[:date])
        next if would_cause_weekend_consecutive?(staff_name, shift[:date])
        shift[:is_working] = true
        daily_counts[shift[:date]] += 1
        added += 1
      end
      # 優先度3: 5日超え連続にはならないが、土日連続になる日（目標日数達成を優先）
      resting.each do |shift|
        break if added >= shortfall
        next if shift[:is_working]
        next if would_cause_consecutive_violation?(staff_name, shift[:date])
        shift[:is_working] = true
        daily_counts[shift[:date]] += 1
        added += 1
      end
      # 優先度4: それでも不足する場合はやむを得ず残りを埋める
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
        next if working.size <= @min_staff_count
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

  # 指定日に出勤させると、その職員の土日連続出勤（fix_weekend_consecutiveが
  # 回避しようとしているもの）を新たに作ってしまわないかを判定する
  def would_cause_weekend_consecutive?(staff_name, date)
    return false unless date.saturday? || date.sunday?
    pair_date = date.saturday? ? date + 1 : date - 1
    pair_shift = @shifts.find { |s| s[:staff_name] == staff_name && s[:date] == pair_date }
    pair_shift&.[](:is_working) == true
  end

  # 指定日に出勤させると、その職員の週勤務日数（weekly_work_days）の
  # 上限を超えてしまわないかを判定する
  def would_exceed_weekly_cap?(staff_name, date)
    cap = @staff_info.dig(staff_name, :weekly_work_days)
    return false unless cap

    week_start = date.beginning_of_week
    current = @shifts.count do |s|
      s[:staff_name] == staff_name && s[:is_working] && s[:date].beginning_of_week == week_start
    end
    current >= cap
  end
end
