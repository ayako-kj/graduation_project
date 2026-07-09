class ShiftsController < ApplicationController
  before_action :authenticate_admin!

  def index
    @target_month = parse_target_month
    @dates = (@target_month.beginning_of_month..@target_month.end_of_month).to_a
    @staffs = Staff.includes(:staff_type).order(:staff_type_id, :name)
    @shift_group = ShiftGroup.find_by(target_month: @target_month.beginning_of_month)

    if @shift_group
      shifts = @shift_group.shifts.includes(:staff)
      @shifts_map = shifts.each_with_object({}) do |shift, hash|
        hash[shift.staff_id] ||= {}
        hash[shift.staff_id][shift.date] = shift
      end
    else
      @shifts_map = {}
    end
  end

  def generate
    target_month = parse_target_month

    staffs = Staff.all
    masker = StaffMasker.new(staffs)
    extractor = ConstraintExtractor.new(target_month)
    constraints = extractor.extract
    builder = PromptBuilder.new(constraints, masker, target_month)
    generator = ShiftGenerator.new(builder)
    result = generator.generate

    unless result[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: result[:error] and return
    end

    parser = ShiftResponseParser.new(masker)
    parsed = parser.parse(result[:content])

    unless parsed[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: parsed[:error] and return
    end

    saver = ShiftSaver.new(target_month, parsed[:shifts])
    saved = saver.save

    unless saved[:success]
      redirect_to shifts_path(month: target_month.strftime("%Y-%m")), alert: saved[:error] and return
    end

    shift_group = saved[:shift_group]
    shifts_for_validation = shift_group.shifts.includes(:staff).map do |s|
      { staff_name: s.staff.name, date: s.date, is_working: s.is_working }
    end
    summary = ShiftValidationSummary.new(shifts_for_validation, target_month)
    summary.save_to_shifts(shift_group)

    redirect_to shifts_path(month: target_month.strftime("%Y-%m")), notice: "シフトを生成しました。"
  end

  private

  def parse_target_month
    if params[:month].present?
      Date.parse("#{params[:month]}-01")
    else
      Date.today.beginning_of_month
    end
  rescue Date::Error
    Date.today.beginning_of_month
  end
end
