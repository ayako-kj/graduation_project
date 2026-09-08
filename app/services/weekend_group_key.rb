# 配置ルール上「どちらかがいればいい」関係にある職種（副館長・行政職・
# 一般事務はteam_minルールで合計1名以上いればよく、同じ枠を共有する）は、
# 土日勤務の公平性（ConstraintExtractorの負債計算・ShiftPostProcessorの
# 割り当て）のどちらでも同じグループとして扱う。館長はこのルールに
# 含まれないため対象外
module WeekendGroupKey
  OVERRIDES = { "副館長" => "配置ルール共有枠", "行政職" => "配置ルール共有枠", "一般事務" => "配置ルール共有枠" }.freeze

  def self.for(staff_type_name)
    OVERRIDES[staff_type_name] || staff_type_name
  end
end
