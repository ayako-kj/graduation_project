class PromptBuilder
  def initialize(constraints, masker, target_month)
    @constraints = constraints
    @masker = masker
    @target_month = target_month
  end

  def system_prompt
    <<~PROMPT
      あなたは公立図書館のシフト管理AIです。
      与えられた制約条件をもとに、対象月の全職員の出勤シフトを作成してください。

      【出力形式】
      JSON形式のみで出力し、説明文は不要です。開館日のみ含め、休館日は省略してください。
      {"shifts":{"YYYY-MM-DD":["Staff_A","Staff_B"],"YYYY-MM-DD":["Staff_C"]}}

      【ルール】
      - 希望休を必ず反映する
      - 特定日は対象グループ全員を出勤にする
      - 休館日は全員休みにする
      - 月の勤務日数目標を守る
      - 開館日は毎日12人以上出勤させる
      - 配置ルールを毎日満たす
      - 土曜と日曜を連続して出勤させない
      - 同じ職員を5日超え連続出勤させない（水〜月の6日連続も違反）
      - 毎日必ず数名は休みにし、月全体で均等に休みを分配する
    PROMPT
  end

  def user_prompt
    lines = []
    lines << "【対象月】#{@target_month.strftime('%Y年%m月')}"
    lines << ""

    lines << "【月の勤務日数目標】"
    lines << "- 正規職員：#{@constraints.dig(:working_days, :regular)}日"
    lines << "- 会計年度任用職員：各職員の個別目標日数（下記職員一覧を参照）"
    lines << ""

    total_staff = @constraints[:staffs].size
    open_days = @target_month.end_of_month.day - @constraints[:closed_days].size
    max_per_day = (total_staff * 0.8).ceil
    lines << "【出勤人数の目安】"
    lines << "- 1日あたり12〜#{max_per_day}名（開館日数：#{open_days}日、職員総数：#{total_staff}名）"
    lines << ""

    wday_names = %w[日 月 火 水 木 金 土]
    regular_target = @constraints.dig(:working_days, :regular)
    lines << "【職員一覧】"
    @constraints[:staffs].each do |staff|
      identifier = @masker.mask(staff[:name])
      target_days = staff[:monthly_target_days] || regular_target
      unavailable = if staff[:unavailable_wdays].any?
        names = staff[:unavailable_wdays].map { |w| "#{wday_names[w]}曜" }.join("・")
        "（#{names}は月1回程度を除き出勤させないこと）"
      else
        ""
      end
      lines << "- #{identifier}：#{staff[:staff_type]}（#{staff[:employment_type]}）今月の目標出勤日数#{target_days}日#{unavailable}"
    end
    lines << ""

    lines << "【配置ルール】"
    if @constraints[:placement_rules].empty?
      lines << "- 設定なし"
    else
      @constraints[:placement_rules].each do |rule|
        case rule[:rule_type]
        when "min_count"
          lines << "- #{rule[:staff_type]}：最低#{rule[:min_count]}名/日"
        when "at_least_one_of"
          lines << "- #{rule[:staff_types].join('・')}のうち1名以上/日"
        when "team_min"
          lines << "- #{rule[:staff_types].join('・')}の合計で最低#{rule[:min_count]}名/日"
        end
      end
    end
    lines << ""

    lines << "【特定日】"
    if @constraints[:special_dates].empty?
      lines << "- なし"
    else
      @constraints[:special_dates].each do |sd|
        parts = []
        if sd[:target_group].present?
          parts << "#{sd[:target_group]}全員出勤"
        end
        if sd[:designated_staffs].any?
          masked_names = sd[:designated_staffs].map { |name| @masker.mask(name) }.join("・")
          parts << "#{masked_names}を出勤させること"
        end
        parts << "全職員出勤" if parts.empty?
        lines << "- #{sd[:date]}（#{sd[:label]}）：#{parts.join('、')}"
      end
    end
    lines << ""

    lines << "【休館日】"
    if @constraints[:closed_days].empty?
      lines << "- なし"
    else
      @constraints[:closed_days].each do |date, label|
        lines << "- #{date.strftime('%Y-%m-%d')}（#{label}）"
      end
    end
    lines << ""

    lines << "【担当会議日（該当担当の職員は全員出勤）】"
    if @constraints[:assignment_constraints].blank?
      lines << "- なし"
    else
      @constraints[:assignment_constraints].each do |ac|
        masked_names = ac[:staff_names].map { |n| @masker.mask(n) }.join("・")
        lines << "- #{ac[:name]}（#{masked_names}）：#{ac[:dates].join('、')}"
      end
    end
    lines << ""

    lines << "【移動図書館巡回日（担当職員は必ず出勤）】"
    if @constraints[:mobile_library_constraints].blank?
      lines << "- なし"
    else
      @constraints[:mobile_library_constraints].each do |mc|
        masked_names = mc[:staff_names].map { |n| @masker.mask(n) }.join("・")
        lines << "- #{mc[:date]}（#{mc[:route_name]}）：#{masked_names}"
      end
    end
    lines << ""

    lines << "【希望休】"
    if @constraints[:leave_requests].empty?
      lines << "- なし"
    else
      @constraints[:leave_requests].each do |lr|
        identifier = @masker.mask(lr[:staff_name])
        reason = lr[:reason].presence ? "（#{lr[:reason]}）" : ""
        lines << "- #{identifier}：#{lr[:date]}#{reason}"
      end
    end

    lines.join("\n")
  end
end
