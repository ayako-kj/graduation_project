class PromptBuilder
  def initialize(constraints, masker, target_month)
    @constraints = constraints
    @masker = masker
    @target_month = target_month
  end

  def system_prompt
    <<~PROMPT
      あなたは公立図書館のシフト管理AIです。
      与えられた制約条件をもとに、対象月の全職員の出勤・休みシフトを作成してください。

      【出力形式】
      以下のJSON形式のみで出力してください。説明文は不要です。
      {
        "shifts": [
          {"staff": "Staff_A", "date": "YYYY-MM-DD", "is_working": true},
          ...
        ]
      }

      【ルール】
      - 各職員の週勤務日数を守ること
      - 職種ごとの最低出勤人数を毎日満たすこと
      - 希望休は必ず反映すること
      - 特定日（全員会議日など）は対象グループ全員を出勤にすること
      - 土日の連続勤務は避けること（土曜・日曜を連続して出勤させないこと）
    PROMPT
  end

  def user_prompt
    lines = []
    lines << "【対象月】#{@target_month.strftime('%Y年%m月')}"
    lines << ""

    lines << "【職員一覧】"
    @constraints[:staffs].each do |staff|
      identifier = @masker.mask(staff[:name])
      weekly = staff[:weekly_work_days] ? "週#{staff[:weekly_work_days]}日" : "週勤務日数未設定"
      lines << "- #{identifier}：#{staff[:staff_type]}（#{staff[:employment_type]}）#{weekly}"
    end
    lines << ""

    lines << "【配置ルール（職種別最低出勤人数）】"
    if @constraints[:placement_rules].empty?
      lines << "- 設定なし"
    else
      @constraints[:placement_rules].each do |rule|
        lines << "- #{rule[:staff_type]}：最低#{rule[:min_count]}名"
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
