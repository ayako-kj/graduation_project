class PlacementRule < ApplicationRecord
  belongs_to :library
  belongs_to :staff_type, optional: true
  belongs_to :employment_type, optional: true

  RULE_TYPES = %w[min_count at_least_one_of team_min].freeze

  validates :rule_type, inclusion: { in: RULE_TYPES }
  validates :min_count, presence: true,
                        numericality: { only_integer: true, greater_than: 0 },
                        if: -> { rule_type.in?(%w[min_count team_min]) }
  validates :staff_type_id, presence: true, if: -> { rule_type == "min_count" }
  validate :validate_staff_type_ids, if: -> { rule_type.in?(%w[at_least_one_of team_min]) }

  def staff_type_ids_array
    return [] if staff_type_ids.blank?
    JSON.parse(staff_type_ids)
  rescue JSON::ParserError
    []
  end

  def display_label
    case rule_type
    when "min_count"
      emp = employment_type ? "（#{employment_type.name}）" : ""
      "#{staff_type.name}#{emp}：最低#{min_count}人"
    when "at_least_one_of"
      names = StaffType.where(id: staff_type_ids_array).order(:sort_order, :id).pluck(:name).join("・")
      "#{names}のいずれか1人以上"
    when "team_min"
      names = StaffType.where(id: staff_type_ids_array).order(:sort_order, :id).pluck(:name).join("・")
      "#{names}の合計：最低#{min_count}人"
    end
  end

  private

  def validate_staff_type_ids
    errors.add(:base, "職種を1つ以上選択してください") if staff_type_ids_array.empty?
  end
end
